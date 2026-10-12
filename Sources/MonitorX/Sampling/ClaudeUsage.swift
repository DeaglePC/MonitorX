import Foundation
import Observation
import AppKit

struct ClaudeQuotaSnapshot: Codable {
    struct Window: Codable {
        let used_percentage: Double?
        let resets_at: Double?
    }
    let updatedAt: Double
    let windows: [String: Window]
    var quotaWindows: [CodexLimitWindow] {
        ["five_hour", "seven_day"].compactMap { key in
            guard let w = windows[key] else { return nil }
            return CodexLimitWindow(usedPercent: w.used_percentage, windowDurationMins: key == "five_hour" ? 300 : 10080, resetsAt: w.resets_at)
        }
    }
}

/// Configures Claude's documented statusLine command. Only quota fields are persisted.
#if !APPSTORE
enum ClaudeUsageBridge {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MonitorX")
    }
    static var configDirectory: URL {
        ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }
    static var snapshotURL: URL { directory.appendingPathComponent("claude-quota.json") }
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func command(in dir: URL) -> String { quote(dir.appendingPathComponent("claude-bridge").path) + " --claude-statusline" }
    static func object(_ url: URL) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw BridgeError.invalidSettings }
        return result
    }
    enum BridgeError: Error { case invalidSettings, changedSettings }
    static func write(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func connected(config: URL = configDirectory, dir: URL = directory) -> Bool {
        guard let settings = try? object(config.appendingPathComponent("settings.json")),
              let status = settings["statusLine"] as? [String: Any] else { return false }
        return status["command"] as? String == command(in: dir)
    }
    static func install(executable: URL, config: URL = configDirectory, dir: URL = directory) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try fm.createDirectory(at: config, withIntermediateDirectories: true)
        let url = config.appendingPathComponent("settings.json")
        var settings = fm.fileExists(atPath: url.path) ? try object(url) : [:]
        let owned = connected(config: config, dir: dir)
        let previous = settings["statusLine"]
        if let previous, !(previous is NSNull), !(previous is [String: Any]) { throw BridgeError.invalidSettings }
        var status = previous as? [String: Any] ?? [:]
        if let type = status["type"] as? String, type != "command" { throw BridgeError.invalidSettings }
        if !owned {
            try write(["previousStatusLine": previous ?? NSNull()], to: dir.appendingPathComponent("claude-statusline-backup.json"))
        }
        // Keep a private helper copy so moving/updating MonitorX does not break Claude's command path.
        try Data(contentsOf: executable).write(to: dir.appendingPathComponent("claude-bridge"), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.appendingPathComponent("claude-bridge").path)
        status["type"] = "command"
        status["command"] = command(in: dir)
        settings["statusLine"] = status
        try write(settings, to: url)
    }
    static func disconnect(config: URL = configDirectory, dir: URL = directory) throws {
        guard connected(config: config, dir: dir) else { throw BridgeError.changedSettings }
        let url = config.appendingPathComponent("settings.json")
        var settings = try object(url)
        let backup = try object(dir.appendingPathComponent("claude-statusline-backup.json"))
        let previous = backup["previousStatusLine"]
        if previous == nil || previous is NSNull { settings.removeValue(forKey: "statusLine") }
        else { settings["statusLine"] = previous }
        try write(settings, to: url)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("claude-quota.json"))
    }
    static func capture(_ data: Data, dir: URL = directory, now: Date = Date()) throws {
        guard data.count < 2 * 1024 * 1024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let limits = root["rate_limits"] as? [String: Any] ?? [:]
        var windows: [String: ClaudeQuotaSnapshot.Window] = [:]
        for key in ["five_hour", "seven_day"] {
            guard let w = limits[key] as? [String: Any],
                  let used = w["used_percentage"] as? Double, used.isFinite, (0...100).contains(used),
                  let reset = w["resets_at"] as? Double, reset > now.timeIntervalSince1970 else { continue }
            windows[key] = .init(used_percentage: used, resets_at: reset)
        }
        // Startup callbacks can omit rate_limits. Keep the last reading and its original timestamp.
        guard !windows.isEmpty else { return }
        let snapshot = ClaudeQuotaSnapshot(updatedAt: now.timeIntervalSince1970, windows: windows)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("claude-quota.json")
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func run(input suppliedInput: Data? = nil, dir: URL = directory) {
        let input = suppliedInput ?? FileHandle.standardInput.readDataToEndOfFile()
        try? capture(input, dir: dir)
        // Forward the original payload to the user's original status line without storing session content.
        let old = try? object(dir.appendingPathComponent("claude-statusline-backup.json"))
        let status = old?["previousStatusLine"] as? [String: Any]
        if let cmd = status?["command"] as? String, !cmd.isEmpty, cmd != command(in: dir) {
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", cmd]
            p.standardInput = pipe
            p.standardOutput = FileHandle.standardOutput
            p.standardError = FileHandle.standardError
            do {
                try p.run()
                try pipe.fileHandleForWriting.write(contentsOf: input)
                try pipe.fileHandleForWriting.close()
                p.waitUntilExit()
            } catch {}
        } else { print("Claude") }
    }
}
#endif

@Observable
final class ClaudeUsageMonitor {
    var snapshot: ClaudeQuotaSnapshot?
    var isConnected = false
    var connectionFailed = false
    var setupStatus: ClaudeCodeSetup.Status = .checking
    #if APPSTORE
    @ObservationIgnored private let fileAccess = QuotaFileAccess(provider: "claude")
    #endif
    #if !APPSTORE
    var usesOAuth = UserDefaults.standard.bool(forKey: "claudeQuotaOAuthConsent")
    var isRefreshing = false
    var errorKey: String?
    var errorMessage: String? {
        guard let errorKey else { return nil }
        switch errorKey {
        case "Claude credentials missing or expired. Sign in again with Claude Code.": return L("Claude credentials missing or expired. Sign in again with Claude Code.")
        case "Claude Keychain access denied. Click Refresh to authorize again.": return L("Claude Keychain access denied. Click Refresh to authorize again.")
        case "Claude quota query is rate limited. Wait a few minutes.": return L("Claude quota query is rate limited. Wait a few minutes.")
        default: return L("Couldn't query Claude usage. Try again later.")
        }
    }
    @ObservationIgnored private var nextQuery = Date.distantPast
    @ObservationIgnored private var generation = 0
    #endif
    @ObservationIgnored private var isCheckingSetup = false
    @ObservationIgnored private var lastSetupCheck = Date.distantPast
    var windows: [CodexLimitWindow] { snapshot?.quotaWindows ?? [] }
    var isStale: Bool {
        guard let snapshot else { return true }
        return connectionFailed || Date().timeIntervalSince1970 - snapshot.updatedAt > 15 * 60 || windows.contains { $0.resetsAt.map { $0 <= Date().timeIntervalSince1970 } ?? false }
    }
    var menuBarRemaining: Double? { windows.compactMap(\.remaining).min() }
    func refresh() {
        #if APPSTORE
        isConnected = fileAccess.isConnected
        if !isConnected { snapshot = nil; connectionFailed = false; return }
        do {
            snapshot = try QuotaSnapshotFile.claude(fileAccess.read())
            connectionFailed = false
        } catch { connectionFailed = true }
        #else
        isConnected = usesOAuth || ClaudeUsageBridge.connected()
        if usesOAuth { queryOAuth(); return }
        if !isConnected { snapshot = nil; return }
        checkSetup()
        snapshot = (try? Data(contentsOf: ClaudeUsageBridge.snapshotURL)).flatMap { try? JSONDecoder().decode(ClaudeQuotaSnapshot.self, from: $0) }
        #endif
    }
    func checkSetup(force: Bool = false) {
        #if !APPSTORE
        guard !isCheckingSetup, force || Date().timeIntervalSince(lastSetupCheck) > (snapshot == nil ? 30 : 300) else { return }
        isCheckingSetup = true
        lastSetupCheck = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = ClaudeCodeSetup.status()
            DispatchQueue.main.async {
                self?.setupStatus = status
                self?.isCheckingSetup = false
            }
        }
        #endif
    }
    func openSetup() {
        #if APPSTORE
        connect()
        #else
        connect()
        #endif
    }
    func connect() {
        #if APPSTORE
        guard fileAccess.choose() else { return }
        snapshot = nil
        #else
        let alert = NSAlert()
        alert.messageText = L("Enable direct Claude query")
        alert.informativeText = L("MonitorX will read Claude Code's local OAuth credentials, including Keychain if needed, and send the access token only to Anthropic to query quota. It will not save or renew the token. Third-party subscription credential use carries Anthropic terms risk. You can revoke access here.")
        alert.addButton(withTitle: L("Allow"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.set(true, forKey: "claudeQuotaOAuthConsent")
        usesOAuth = true
        generation += 1
        snapshot = nil
        errorKey = nil
        connectionFailed = false
        nextQuery = .distantPast
        isConnected = true
        queryOAuth(force: true, allowKeychainPrompt: true)
        #endif
        refresh()
    }
    func disconnect() {
        #if APPSTORE
        fileAccess.disconnect()
        #else
        if usesOAuth {
            UserDefaults.standard.removeObject(forKey: "claudeQuotaOAuthConsent")
            usesOAuth = false
            generation += 1
            snapshot = nil
            errorKey = nil
            connectionFailed = false
        }
        if ClaudeUsageBridge.connected() {
            do { try ClaudeUsageBridge.disconnect(); connectionFailed = false }
            catch { connectionFailed = true }
        }
        #endif
        refresh()
    }
    #if !APPSTORE
    func queryOAuth(force: Bool = false, allowKeychainPrompt: Bool = false) {
        guard usesOAuth, !isRefreshing, Date() >= nextQuery || force else { return }
        // 429 backoff also applies to manual refresh; it must not hammer the endpoint.
        if errorKey == "Claude quota query is rate limited. Wait a few minutes." && Date() < nextQuery { return }
        isRefreshing = true
        nextQuery = Date().addingTimeInterval(300)
        let requestGeneration = generation
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try ClaudeOAuthUsage.read(allowKeychainPrompt: allowKeychainPrompt) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                guard self.usesOAuth, self.generation == requestGeneration else {
                    if self.usesOAuth { self.queryOAuth(force: true) }
                    return
                }
                switch result {
                case .success(let value): self.snapshot = value; self.errorKey = nil; self.connectionFailed = false
                case .failure(let error):
                    self.connectionFailed = true
                    switch error {
                    case ClaudeOAuthUsage.Failure.credentials, ClaudeOAuthUsage.Failure.authentication:
                        self.errorKey = "Claude credentials missing or expired. Sign in again with Claude Code."
                    case ClaudeOAuthUsage.Failure.keychainDenied:
                        self.errorKey = "Claude Keychain access denied. Click Refresh to authorize again."
                    case ClaudeOAuthUsage.Failure.rateLimited(let delay):
                        self.nextQuery = Date().addingTimeInterval(delay)
                        self.errorKey = "Claude quota query is rate limited. Wait a few minutes."
                    default: self.errorKey = "Couldn't query Claude usage. Try again later."
                    }
                }
            }
        }
    }
    #endif

}
