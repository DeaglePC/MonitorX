#if !APPSTORE
import Foundation
import CoreFoundation
import Security
import LocalAuthentication

/// CodexBar-style OAuth usage query. Official Claude Code owns login and token renewal.
enum ClaudeOAuthUsage {
    enum Failure: Error { case credentials, keychainDenied, authentication, rateLimited(TimeInterval), unavailable, invalidResponse }

    static func token(_ data: Data, now: Date = Date()) throws -> String {
        guard data.count <= 1024 * 1024,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              (16...16384).contains(token.count), token.utf8.allSatisfy({ (33...126).contains($0) }) else { throw Failure.credentials }
        if let expiry = oauth["expiresAt"], !(expiry is NSNull) {
            guard let number = expiry as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { throw Failure.credentials }
            guard number.doubleValue / 1000 > now.timeIntervalSince1970 else { throw Failure.authentication }
        }
        if let scopes = oauth["scopes"] as? [String], !scopes.contains("user:profile") { throw Failure.credentials }
        return token
    }

    static func readToken(allowKeychainPrompt: Bool) throws -> String {
        // Respect an explicitly configured profile; never substitute the default account for it.
        let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        let directory = custom.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let file = directory.appendingPathComponent(".credentials.json")
        if FileManager.default.fileExists(atPath: file.path) {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            return try token(handle.read(upToCount: 1024 * 1024 + 1) ?? Data())
        }
        guard custom == nil else { throw Failure.credentials }
        let context = LAContext()
        context.interactionNotAllowed = !allowKeychainPrompt
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled { throw Failure.keychainDenied }
        guard status == errSecSuccess, let data = item as? Data else { throw Failure.credentials }
        return try token(data)
    }

    static func request(accessToken: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("MonitorX/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func read(allowKeychainPrompt: Bool = false) throws -> ClaudeQuotaSnapshot {
        let request = request(accessToken: try readToken(allowKeychainPrompt: allowKeychainPrompt))
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForResource = 20
        let delegate = CodexOAuthUsage.Response()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: request).resume()
        guard delegate.done.wait(timeout: .now() + 21) == .success else { throw Failure.unavailable }
        let (body, status, error) = delegate.result()
        guard error == nil else { throw Failure.unavailable }
        if status == 401 || status == 403 { throw Failure.authentication }
        if status == 429 { throw Failure.rateLimited(retryDelay(delegate.retryAfterHeader())) }
        guard status == 200 else { throw Failure.unavailable }
        return try parse(body)
    }

    static func retryDelay(_ header: String?, now: Date = Date()) -> TimeInterval {
        guard let header else { return 300 }
        if let seconds = Double(header), seconds.isFinite, seconds >= 0 { return max(300, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return max(300, formatter.date(from: header)?.timeIntervalSince(now) ?? 300)
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> ClaudeQuotaSnapshot {
        guard data.count <= 1024 * 1024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidResponse }
        var windows: [String: ClaudeQuotaSnapshot.Window] = [:]
        let formatter = ISO8601DateFormatter()
        for key in ["five_hour", "seven_day"] {
            guard let value = root[key], !(value is NSNull) else { continue }
            guard let row = value as? [String: Any], let number = row["utilization"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  (0...100).contains(number.doubleValue) else { throw Failure.invalidResponse }
            var reset: Double?
            if let value = row["resets_at"], !(value is NSNull) {
                guard let text = value as? String else { throw Failure.invalidResponse }
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                var date = formatter.date(from: text)
                if date == nil { formatter.formatOptions = [.withInternetDateTime]; date = formatter.date(from: text) }
                guard let date else { throw Failure.invalidResponse }
                reset = date.timeIntervalSince1970
                guard reset!.isFinite, reset! > 0 else { throw Failure.invalidResponse }
            }
            windows[key] = .init(used_percentage: number.doubleValue, resets_at: reset)
        }
        guard !windows.isEmpty else { throw Failure.invalidResponse }
        return ClaudeQuotaSnapshot(updatedAt: now.timeIntervalSince1970, windows: windows)
    }
}
#endif
