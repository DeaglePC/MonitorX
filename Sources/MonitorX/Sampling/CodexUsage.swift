import AppKit
import Observation

struct CodexLimitWindow: Codable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?
    var remaining: Double? { usedPercent.map { max(0, min(100, 100 - $0)) } }
    var duration: String {
        guard let minutes = windowDurationMins else { return "—" }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = Localizer.shared.locale
        formatter.calendar = calendar
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "—"
    }
}

struct CodexLimitBucket: Codable {
    let limitId: String?
    let limitName: String?
    let primary: CodexLimitWindow?
    let secondary: CodexLimitWindow?
    var windows: [CodexLimitWindow] { [primary, secondary].compactMap { $0 } }
    var title: String { limitName ?? limitId ?? "Codex" }
}

struct CodexLimitsResponse: Decodable {
    let rateLimits: CodexLimitBucket?
    let rateLimitsByLimitId: [String: CodexLimitBucket]?
    var buckets: [CodexLimitBucket] {
        if let map = rateLimitsByLimitId, !map.isEmpty {
            return map.keys.sorted().compactMap { map[$0] }
        }
        return rateLimits.map { [$0] } ?? []
    }
}

@Observable
final class CodexUsageMonitor {
    @ObservationIgnored var onUpdate: (() -> Void)?
    var buckets: [CodexLimitBucket] = []
    var updatedAt: Date?
    var isRefreshing = false
    var errorKey: String?
    #if APPSTORE
    @ObservationIgnored private let fileAccess = QuotaFileAccess(provider: "codex")
    var isConnected: Bool { fileAccess.isConnected }
    #else
    var usesOAuth = UserDefaults.standard.bool(forKey: "codexQuotaOAuthConsent")
    #endif
    var isStale: Bool {
        guard let updatedAt else { return true }
        return errorKey != nil || Date().timeIntervalSince(updatedAt) > 900
            || buckets.flatMap(\.windows).contains { ($0.resetsAt ?? .greatestFiniteMagnitude) <= Date().timeIntervalSince1970 }
    }
    var errorMessage: String {
        if errorKey == "Couldn't read quota file. Select a valid quota snapshot again." {
            return L("Couldn't read quota file. Select a valid quota snapshot again.")
        }
        return errorKey == "Codex CLI not found" ? L("Codex CLI not found") : L("Couldn't read Codex usage. Sign in to Codex with ChatGPT.")
    }

    func connect() {
        #if APPSTORE
        guard fileAccess.choose() else { return }
        #else
        let alert = NSAlert()
        alert.messageText = L("Enable direct Codex query")
        alert.informativeText = L("MonitorX will read the access token from your local Codex auth.json and send it only to ChatGPT to query quota. It will not save or refresh the token. You can revoke this access here.")
        alert.addButton(withTitle: L("Allow"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.set(true, forKey: "codexQuotaOAuthConsent")
        usesOAuth = true
        #endif
        restartAfterSourceChange()
    }

    func disconnect() {
        #if APPSTORE
        fileAccess.disconnect()
        #else
        UserDefaults.standard.removeObject(forKey: "codexQuotaOAuthConsent")
        usesOAuth = false
        #endif
        restartAfterSourceChange()
    }

    private func restartAfterSourceChange() {
        let wasEnabled = enabled
        setEnabled(false)
        buckets = []; updatedAt = nil; errorKey = nil
        setEnabled(wasEnabled)
        onUpdate?()
    }
    /// The main Codex bucket's most restrictive known window; never combine unrelated model buckets.
    var menuBarRemaining: Double? {
        let bucket = buckets.first { $0.limitId == "codex" } ?? buckets.first
        return bucket?.windows.compactMap(\.remaining).min()
    }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var generation = 0

    func setEnabled(_ on: Bool) {
        guard enabled != on else { return }
        enabled = on
        generation += 1
        timer?.invalidate()
        timer = nil
        if on {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: Edition.isAppStore ? 5 : 300, repeats: true) { [weak self] _ in self?.refresh() }
        }
    }

    func shutdown() { setEnabled(false) }

    func refresh() {
        guard enabled, !isRefreshing else { return }
        #if APPSTORE
        guard isConnected else { return }
        #else
        let allowOAuth = usesOAuth
        #endif
        isRefreshing = true
        let requestGeneration = generation
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { () -> (CodexLimitsResponse, Date) in
                #if APPSTORE
                guard let self else { throw QuotaSnapshotFile.Invalid.snapshot }
                let snapshot = try QuotaSnapshotFile.codex(self.fileAccess.read())
                let map = Dictionary(uniqueKeysWithValues: snapshot.buckets.enumerated().map { (String($0.offset), $0.element) })
                return (CodexLimitsResponse(rateLimits: nil, rateLimitsByLimitId: map), Date(timeIntervalSince1970: snapshot.updatedAt))
                #else
                return (try CodexUsageReader.readPreferred(allowOAuth: allowOAuth), Date())
                #endif
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                guard self.enabled else { return }
                guard self.generation == requestGeneration else { self.refresh(); return }
                switch result {
                case .success(let (response, capturedAt)):
                    self.buckets = response.buckets
                    self.updatedAt = capturedAt
                    self.errorKey = nil
                case .failure(let error):
                    // Retain the last reading, with an explicit error and its original timestamp.
                    #if APPSTORE
                    self.errorKey = "Couldn't read quota file. Select a valid quota snapshot again."
                    #else
                    self.errorKey = error is CodexUsageReader.MissingExecutable ? "Codex CLI not found" : "Couldn't read Codex usage. Sign in to Codex with ChatGPT."
                    #endif
                }
                self.onUpdate?()
            }
        }
    }
}

/// Read-only JSON-RPC over the official CLI's app-server; credentials stay inside Codex.
enum CodexUsageReader {
    struct MissingExecutable: Error {}
    struct Unavailable: Error {}

    #if !APPSTORE
    static func readPreferred(allowOAuth: Bool) throws -> CodexLimitsResponse {
        if allowOAuth {
            do { return try CodexOAuthUsage.read() }
            catch CodexOAuthUsage.Failure.credentials { /* unavailable source: try official CLI */ }
            catch CodexOAuthUsage.Failure.authentication { /* CLI owns credential renewal */ }
        }
        // Network/server/decode errors do not silently switch data sources.
        return try read()
    }
    #endif

    static func read(executable: URL? = nil, timeoutInterval: TimeInterval = 20) throws -> CodexLimitsResponse {
        #if APPSTORE
        throw Unavailable()
        #else
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Applications/Codex.app/Contents/Resources/codex"]
        guard let launcher = executable ?? candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map({ URL(fileURLWithPath: $0) }) else {
            throw MissingExecutable()
        }
        var binary = launcher
        if executable == nil, launcher.resolvingSymlinksInPath().pathExtension == "js" {
            // npm ships the official native executable beside its Node launcher.
            // Prefer it so Finder launch does not depend on the user's Node environment.
            #if arch(arm64)
            let platform = "arm64", triple = "aarch64-apple-darwin"
            #else
            let platform = "x64", triple = "x86_64-apple-darwin"
            #endif
            let root = launcher.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
            let native = root.appendingPathComponent("node_modules/@openai/codex-darwin-\(platform)/vendor/\(triple)/bin/codex")
            if FileManager.default.isExecutableFile(atPath: native.path) { binary = native }
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["app-server"]
        // Finder-launched apps have a minimal PATH; npm's official Codex launcher needs Node.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin") + ":/opt/homebrew/bin:/usr/local/bin"
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutInterval, execute: timeout)
        defer {
            timeout.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            // Bound cleanup even if an app-server fails to respond to SIGTERM.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "monitorx", "version": "1.0"]]])
        var buffer = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { throw Unavailable() }
            buffer.append(chunk)
            guard buffer.count < 2 * 1024 * 1024 else { throw Unavailable() }
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any], let id = message["id"] as? Int else { continue }
                guard message["error"] == nil else { throw Unavailable() }
                if id == 1 {
                    try send(["method": "initialized", "params": [:]])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else if id == 2, let result = message["result"] {
                    return try JSONDecoder().decode(CodexLimitsResponse.self, from: JSONSerialization.data(withJSONObject: result))
                }
            }
        }
        #endif
    }
}
