import Foundation

@main
struct CodexUsageCheck {
    static func main() throws {
        let fixture = #"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":9,"windowDurationMins":10080,"resetsAt":1791948757},"secondary":null},"other":{"limitId":"other","primary":{"usedPercent":105},"secondary":{"usedPercent":-5}}}}"#
        let decoded = try JSONDecoder().decode(CodexLimitsResponse.self, from: Data(fixture.utf8))
        precondition(decoded.buckets.count == 2)
        precondition(decoded.buckets[0].windows.count == 1, "Missing windows must not be synthesized")
        precondition(decoded.buckets[0].windows[0].remaining == 91)
        precondition(decoded.buckets[0].windows[0].resetsAt == 1791948757)
        precondition(decoded.buckets[1].windows[0].remaining == 0)
        precondition(decoded.buckets[1].windows[1].remaining == 100)
        let usage = CodexUsageMonitor()
        usage.buckets = decoded.buckets
        precondition(usage.menuBarRemaining == 91, "Menu bar must prefer the Codex bucket over unrelated model limits")
        let dualWindow = try JSONDecoder().decode(CodexLimitsResponse.self, from: Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20},"secondary":{"usedPercent":75}}}"#.utf8))
        usage.buckets = dualWindow.buckets
        precondition(usage.menuBarRemaining == 25, "Menu bar must show the most restrictive Codex window")
        let missing = try JSONDecoder().decode(CodexLimitsResponse.self, from: Data(#"{"rateLimits":{"primary":{}}}"#.utf8))
        precondition(missing.buckets[0].windows[0].remaining == nil)
        usage.buckets = missing.buckets
        precondition(usage.menuBarRemaining == nil, "Unavailable quota must never look like 100% remaining")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("codex")
        func script(_ text: String) throws {
            try text.write(to: fake, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        }
        try script("""
        #!/bin/sh
        read -r init
        case "$init" in *initialize*) ;; *) exit 1;; esac
        echo '{"id":1,"result":{}}'
        read -r ready
        case "$ready" in *initialized*) ;; *) exit 1;; esac
        read -r request
        case "$request" in *rateLimits*read*) ;; *) exit 1;; esac
        echo '{"id":2,"result":\(fixture)}'
        """)
        let result = try CodexUsageReader.read(executable: fake)
        precondition(result.buckets[0].windows[0].remaining == 91)
        try script("#!/bin/sh\necho '{\"id\":1,\"error\":{\"code\":401}}'\n")
        do { _ = try CodexUsageReader.read(executable: fake); fatalError("Must reject RPC errors") }
        catch is CodexUsageReader.Unavailable {}
        try script("#!/bin/sh\nwhile read -r line; do :; done\n")
        let start = Date()
        do { _ = try CodexUsageReader.read(executable: fake, timeoutInterval: 0.2); fatalError("Must time out") }
        catch is CodexUsageReader.Unavailable {}
        precondition(Date().timeIntervalSince(start) < 3, "Stalled server must not block monitoring")
        if CommandLine.arguments.contains("--live") {
            let actual = try CodexUsageReader.read()
            precondition(!actual.buckets.isEmpty)
            print("Live Codex read passed: \(actual.buckets.count) quota bucket(s)")
        }
        print("Codex usage passed: multi-bucket preference, missing fields, percent clamping, reset time, RPC handshake, errors and timeout")
    }
}
