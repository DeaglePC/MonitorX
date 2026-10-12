import Foundation
@main struct ClaudeOAuthCheck {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let secret = "TEST-TOKEN-DO-NOT-STORE"
        let credentials = "{\"claudeAiOauth\":{\"accessToken\":\"\(secret)\",\"refreshToken\":\"DO-NOT-USE\",\"expiresAt\":1800003600000,\"scopes\":[\"user:profile\"]}}"
        let token = try ClaudeOAuthUsage.token(Data(credentials.utf8), now: now)
        precondition(token == secret)
        func rejectToken(_ value: String) {
            do { _ = try ClaudeOAuthUsage.token(Data(value.utf8), now: now); fatalError("Invalid token accepted") } catch {}
        }
        rejectToken(credentials.replacingOccurrences(of: "1800003600000", with: "1700003600000"))
        rejectToken(credentials.replacingOccurrences(of: "user:profile", with: "user:inference"))
        rejectToken(credentials.replacingOccurrences(of: "1800003600000", with: "true"))
        rejectToken(credentials.replacingOccurrences(of: secret, with: "short"))
        rejectToken("{\"apiKey\":\"\(secret)\"}")
        let input = #"{"five_hour":{"utilization":27.5,"resets_at":"2027-01-15T09:00:00.123Z"},"seven_day":{"utilization":65,"resets_at":"2027-01-20T09:00:00+00:00"},"extra_usage":{"private":"TEST-TOKEN-DO-NOT-STORE"}}"#
        let snapshot = try ClaudeOAuthUsage.parse(Data(input.utf8), now: now)
        precondition(snapshot.quotaWindows.count == 2 && snapshot.updatedAt == now.timeIntervalSince1970)
        precondition(snapshot.quotaWindows.compactMap(\.remaining).min() == 35)
        let stored = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        precondition(!stored.contains(secret) && !stored.contains("private"))
        for input in ["{}", input.replacingOccurrences(of: "27.5", with: "true"), input.replacingOccurrences(of: "27.5", with: "101"), input.replacingOccurrences(of: "2027-01-15T09:00:00.123Z", with: "bad-date")] {
            do { _ = try ClaudeOAuthUsage.parse(Data(input.utf8)); fatalError("Invalid usage accepted") } catch {}
        }
        let missing = try ClaudeOAuthUsage.parse(Data(#"{"five_hour":null,"seven_day":{"utilization":20,"resets_at":null}}"#.utf8), now: now)
        precondition(missing.quotaWindows.count == 1 && missing.quotaWindows[0].resetsAt == nil)
        precondition(ClaudeOAuthUsage.retryDelay("900") == 900)
        precondition(ClaudeOAuthUsage.retryDelay("0") == 300)
        precondition(ClaudeOAuthUsage.retryDelay("invalid") == 300)
        let request = ClaudeOAuthUsage.request(accessToken: secret)
        precondition(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        precondition(request.value(forHTTPHeaderField:"Authorization") == "Bearer " + secret)
        precondition(request.value(forHTTPHeaderField:"anthropic-beta") == "oauth-2025-04-20")
        print("Claude OAuth passed: expiry/scopes, quota parsing, missing windows, secret exclusion and fixed endpoint")
    }
}
