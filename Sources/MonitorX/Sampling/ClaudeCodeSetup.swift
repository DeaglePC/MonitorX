import AppKit

/// Uses the CLI's public auth command; MonitorX never reads or stores credentials.
enum ClaudeCodeSetup {
    enum Status: Equatable { case checking, missing, signedOut, signedIn, unsupported, unavailable }

    static func executable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/claude" }
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }

    static func parseStatus(_ data: Data) -> Status {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loggedIn = object["loggedIn"] as? Bool else { return .unavailable }
        guard loggedIn else { return .signedOut }
        guard let method = object["authMethod"] as? String else { return .unavailable }
        return ["claude.ai", "oauth_token"].contains(method) ? .signedIn : .unsupported
    }

    static func status(executable supplied: URL? = nil, timeoutInterval: TimeInterval = 8) -> Status {
        guard let binary = supplied ?? executable() else { return .missing }
        let process = Process(), output = Pipe()
        process.executableURL = binary
        process.arguments = ["auth", "status"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = (environment["PATH"] ?? "/usr/bin:/bin") + ":/opt/homebrew/bin:/usr/local/bin"
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .unavailable }
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutInterval, execute: timeout)
        defer { timeout.cancel(); try? output.fileHandleForReading.close() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard data.count < 1024 * 1024, [0, 1].contains(process.terminationStatus) else { return .unavailable }
        return parseStatus(data)
    }

    static func launcher(executable: URL, config: URL, session: URL, needsLogin: Bool) -> String {
        let binary = ClaudeUsageBridge.quote(executable.path)
        return """
        #!/bin/zsh -l
        export CLAUDE_CONFIG_DIR=\(ClaudeUsageBridge.quote(config.path))
        cd \(ClaudeUsageBridge.quote(session.path)) || exit 1
        \(needsLogin ? binary + " auth login || exit $?" : "")
        exec \(binary)

        """
    }

    static func open(needsLogin: Bool, completion: @escaping (Bool) -> Void) throws {
        guard let binary = executable() else {
            completion(NSWorkspace.shared.open(URL(string: "https://code.claude.com/docs/en/quickstart")!))
            return
        }
        let directory = ClaudeUsageBridge.directory
        // A dedicated empty working folder avoids project statusLine overrides and project access.
        let session = directory.appendingPathComponent("Claude Setup", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("Open Claude Code.command")
        try Data(launcher(executable: binary, config: ClaudeUsageBridge.configDirectory,
                          session: session, needsLogin: needsLogin).utf8).write(to: script, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: .init()) { _, error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }
}
