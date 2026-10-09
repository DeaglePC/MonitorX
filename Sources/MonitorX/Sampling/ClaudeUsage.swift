import Foundation
import Observation

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

@Observable
final class ClaudeUsageMonitor {
    var snapshot: ClaudeQuotaSnapshot?
    var isConnected = false
    var connectionFailed = false
    var setupStatus: ClaudeCodeSetup.Status = .checking
    @ObservationIgnored private var isCheckingSetup = false
    @ObservationIgnored private var lastSetupCheck = Date.distantPast
    var windows: [CodexLimitWindow] { snapshot?.quotaWindows ?? [] }
    var isStale: Bool {
        guard let snapshot else { return true }
        return Date().timeIntervalSince1970 - snapshot.updatedAt > 15 * 60 || windows.contains { ($0.resetsAt ?? 0) <= Date().timeIntervalSince1970 }
    }
    var menuBarRemaining: Double? { windows.compactMap(\.remaining).min() }
    func refresh() {
        isConnected = ClaudeUsageBridge.connected()
        checkSetup()
        if !isConnected { snapshot = nil; return }
        snapshot = (try? Data(contentsOf: ClaudeUsageBridge.snapshotURL)).flatMap { try? JSONDecoder().decode(ClaudeQuotaSnapshot.self, from: $0) }
    }
    func checkSetup(force: Bool = false) {
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
    }
    func openSetup() {
        if !isConnected && ClaudeCodeSetup.executable() != nil { connect() }
        guard !connectionFailed else { return }
        do {
            try ClaudeCodeSetup.open(needsLogin: setupStatus == .signedOut || setupStatus == .unsupported) { [weak self] success in
                self?.connectionFailed = !success
                self?.checkSetup(force: true)
            }
        } catch { connectionFailed = true }
    }
    func connect() {
        do {
            guard let executable = Bundle.main.executableURL else { return }
            try ClaudeUsageBridge.install(executable: executable)
            connectionFailed = false
        } catch { connectionFailed = true }
        refresh()
    }
    func disconnect() {
        do { try ClaudeUsageBridge.disconnect(); connectionFailed = false }
        catch { connectionFailed = true }
        refresh()
    }
}
