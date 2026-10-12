import Foundation

@main
struct QuotaAccessCheck {
    static func main() throws {
        let now = Date().timeIntervalSince1970
        let reset = now + 3600
        let codex = """
        {"provider":"codex","updatedAt":\(now),"buckets":[{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":\(reset)}}]}
        """
        let decoded = try QuotaSnapshotFile.codex(Data(codex.utf8))
        precondition(decoded.buckets[0].primary?.remaining == 75)
        precondition(decoded.updatedAt == now)
        let claude = """
        {"updatedAt":\(now),"windows":{"five_hour":{"used_percentage":35,"resets_at":\(reset)}}}
        """
        let claudeDecoded = try QuotaSnapshotFile.claude(Data(claude.utf8))
        precondition(claudeDecoded.quotaWindows[0].remaining == 65)
        func rejects(_ input: String, claude: Bool = false) {
            do {
                if claude { _ = try QuotaSnapshotFile.claude(Data(input.utf8)) }
                else { _ = try QuotaSnapshotFile.codex(Data(input.utf8)) }
                fatalError("Must reject invalid or credential-bearing quota input")
            } catch {}
        }
        rejects(#"{"auth_mode":"chatgpt","tokens":{"access_token":"PRIVATE"}}"#)
        rejects(codex.replacingOccurrences(of: "\"provider\":\"codex\"", with: "\"provider\":\"claude\""))
        rejects(codex.replacingOccurrences(of: "\"usedPercent\":25", with: "\"usedPercent\":101"))
        rejects(codex.replacingOccurrences(of: "\"usedPercent\":25", with: "\"usedPercent\":true"))
        rejects(codex.replacingOccurrences(of: "\"usedPercent\":25", with: "\"usedPercent\":25,\"access_token\":\"PRIVATE\""))
        rejects(codex.replacingOccurrences(of: "\"windowDurationMins\":300", with: "\"windowDurationMins\":0"))
        rejects(codex.replacingOccurrences(of: "\"updatedAt\":\(now)", with: "\"updatedAt\":\(now + 3600)"))
        rejects(String(repeating: " ", count: 65537))
        rejects(claude.replacingOccurrences(of: "\"used_percentage\":35", with: "\"used_percentage\":35,\"prompt\":\"PRIVATE\""), claude: true)
        rejects("{\"updatedAt\":\(now),\"windows\":{}}", claude: true)
        let usage = CodexUsageMonitor()
        usage.buckets = decoded.buckets
        usage.updatedAt = Date(timeIntervalSince1970: now)
        precondition(!usage.isStale)
        usage.updatedAt = Date(timeIntervalSince1970: now - 901)
        precondition(usage.isStale, "Polling a snapshot must not renew the source timestamp")
        #if APPSTORE
        let suite = "monitorx.quota-check." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = QuotaFileAccess(provider: "codex", defaults: defaults)
        precondition(!access.isConnected)
        defaults.set(Data("invalid bookmark".utf8), forKey: "quotaSnapshotBookmark.codex")
        precondition(access.isConnected)
        do { _ = try access.read(); fatalError("Invalid grants must fail closed") } catch {}
        access.disconnect()
        precondition(!access.isConnected)
        do { _ = try access.read(); fatalError("Revoked grants must not read files") } catch {}
        #else
        let creds = try CodexOAuthUsage.credentials(Data(#"{"tokens":{"access_token":"FAKE-ACCESS-TOKEN-ONLY","account_id":"test-account"}}"#.utf8))
        precondition(creds.accountID == "test-account")
        let payload = Data("{\"exp\":1}".utf8).base64EncodedString()
        do {
            _ = try CodexOAuthUsage.credentials(Data("{\"tokens\":{\"access_token\":\"header.\(payload).signature\"}}".utf8))
            fatalError("Expired token must fall back to its official owner")
        } catch CodexOAuthUsage.Failure.authentication {}
        do {
            _ = try CodexOAuthUsage.credentials(Data(#"{"auth_mode":"apikey","tokens":{"access_token":"FAKE-ACCESS-TOKEN-ONLY"}}"#.utf8))
            fatalError("API-key credentials are not subscription auth")
        } catch CodexOAuthUsage.Failure.credentials {}
        let response = try CodexOAuthUsage.parse(Data("""
        {"rate_limit":{"primary_window":{"used_percent":25,"limit_window_seconds":18000,"reset_at":\(reset)}},"additional_rate_limits":[{"metered_feature":"codex-spark","limit_name":"Spark","rate_limit":{"secondary_window":{"used_percent":80,"limit_window_seconds":604800,"reset_at":\(reset)}}}],"email":"DO-NOT-EXPORT"}
        """.utf8))
        precondition(response.buckets.count == 2)
        precondition(response.buckets[1].limitId == "codex-spark")
        precondition(response.buckets[1].secondary?.remaining == 20)
        precondition(response.buckets[0].secondary == nil, "Missing windows must stay absent")
        let safe = try JSONEncoder().encode(QuotaSnapshotFile.Codex(provider: "codex", updatedAt: now, buckets: response.buckets))
        precondition(!String(decoding: safe, as: UTF8.self).contains("DO-NOT-EXPORT"))
        _ = try QuotaSnapshotFile.codex(safe)
        do { _ = try CodexOAuthUsage.parse(Data("{}".utf8)); fatalError("Missing quota must not appear as unused") }
        catch CodexOAuthUsage.Failure.invalidResponse {}
        if CommandLine.arguments.contains("--live") {
            do {
                let live = try CodexOAuthUsage.read()
                precondition(!live.buckets.isEmpty)
                print("Live direct Codex query passed; account identity, quota values and credentials omitted")
            } catch {
                print("Live direct Codex query unavailable; no account data printed")
                throw CodexOAuthUsage.Failure.unavailable
            }
        }
        #endif
        print("Quota access passed: credential rejection, quota-only schema, timestamps, stale readings and edition-specific access")
    }
}
