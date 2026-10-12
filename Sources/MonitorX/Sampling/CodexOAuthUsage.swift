#if !APPSTORE
import Foundation
import CoreFoundation

/// CodexBar-style direct usage query. Login and token renewal remain owned by the official CLI.
/// Compiled out of the App Store edition, including the endpoint and credential paths.
enum CodexOAuthUsage {
    enum Failure: Error { case credentials, authentication, unavailable, invalidResponse }
    struct Credentials {
        let accessToken: String
        let accountID: String?
    }

    static func credentials(_ data: Data, now: Date = Date()) throws -> Credentials {
        guard data.count <= 1024 * 1024,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["auth_mode"] == nil || root["auth_mode"] is NSNull || root["auth_mode"] as? String == "chatgpt",
              let tokens = root["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String,
              (16...16384).contains(token.count), token.utf8.allSatisfy({ (33...126).contains($0) }) else { throw Failure.credentials }
        // Check expiry when the access token is a JWT; do not refresh or rewrite shared credentials.
        let parts = token.split(separator: ".")
        if parts.count == 3 {
            var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            if let bytes = Data(base64Encoded: payload),
               let claims = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
               let expires = claims["exp"] as? Double, expires <= now.timeIntervalSince1970 { throw Failure.authentication }
        }
        let account = tokens["account_id"] as? String
        if let account {
            guard !account.isEmpty, account.count <= 256, account.utf8.allSatisfy({ (33...126).contains($0) }) else { throw Failure.credentials }
        }
        return Credentials(accessToken: token, accountID: account)
    }

    static func read() throws -> CodexLimitsResponse {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let file = home.appendingPathComponent("auth.json")
        guard let handle = try? FileHandle(forReadingFrom: file) else { throw Failure.credentials }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
        let credentials = try credentials(data)
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer " + credentials.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MonitorX/1.0", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForResource = 20
        let delegate = Response()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: request).resume()
        guard delegate.done.wait(timeout: .now() + 21) == .success else { throw Failure.unavailable }
        let (body, status, error) = delegate.result()
        guard error == nil else { throw Failure.unavailable }
        if status == 401 || status == 403 { throw Failure.authentication }
        guard status == 200 else { throw Failure.unavailable }
        return try parse(body)
    }

    static func parse(_ data: Data) throws -> CodexLimitsResponse {
        guard data.count <= 1024 * 1024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidResponse }
        func window(_ value: Any?) throws -> CodexLimitWindow? {
            guard let value, !(value is NSNull) else { return nil }
            guard let row = value as? [String: Any] else { throw Failure.invalidResponse }
            for key in ["used_percent", "limit_window_seconds", "reset_at"] {
                if let value = row[key], !(value is NSNull) {
                    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { throw Failure.invalidResponse }
                }
            }
            let used = row["used_percent"] as? Double
            let seconds = row["limit_window_seconds"] as? Int
            let reset = row["reset_at"] as? Double
            if let used { guard used.isFinite, (0...100).contains(used) else { throw Failure.invalidResponse } }
            if let seconds { guard (60...31_536_000).contains(seconds), seconds % 60 == 0 else { throw Failure.invalidResponse } }
            if let reset { guard reset.isFinite, reset > 0 else { throw Failure.invalidResponse } }
            return CodexLimitWindow(usedPercent: used, windowDurationMins: seconds.map { $0 / 60 }, resetsAt: reset)
        }
        func bucket(_ rate: [String: Any], id: String, name: String?) throws -> CodexLimitBucket {
            CodexLimitBucket(limitId: id, limitName: name,
                             primary: try window(rate["primary_window"]), secondary: try window(rate["secondary_window"]))
        }
        var map: [String: CodexLimitBucket] = [:]
        if let rate = root["rate_limit"] as? [String: Any] { map["codex"] = try bucket(rate, id: "codex", name: nil) }
        if let extras = root["additional_rate_limits"] as? [[String: Any]] {
            guard extras.count <= 31 else { throw Failure.invalidResponse }
            for (index, extra) in extras.enumerated() {
                guard let rate = extra["rate_limit"] as? [String: Any] else { continue }
                let id = extra["limit_id"] as? String ?? extra["metered_feature"] as? String ?? "codex-extra-\(index)"
                guard id != "codex", map[id] == nil, id.count <= 100 else { throw Failure.invalidResponse }
                let name = extra["limit_name"] as? String
                guard name == nil || name!.count <= 100 else { throw Failure.invalidResponse }
                map[id] = try bucket(rate, id: id, name: name)
            }
        }
        guard map.values.flatMap(\.windows).contains(where: { $0.usedPercent != nil }) else { throw Failure.invalidResponse }
        return CodexLimitsResponse(rateLimits: map["codex"], rateLimitsByLimitId: map)
    }

    final class Response: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var body = Data()
        private var status: Int?
        private var retryAfter: String?
        private var error: Error?
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil) // Never forward a subscription token to another location.
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            if body.count + data.count > 1024 * 1024 {
                error = Failure.invalidResponse
                lock.unlock()
                dataTask.cancel()
            } else { body.append(data); lock.unlock() }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            status = (task.response as? HTTPURLResponse)?.statusCode
            retryAfter = (task.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
            self.error = self.error ?? error
            lock.unlock()
            done.signal()
        }
        func retryAfterHeader() -> String? {
            lock.lock(); defer { lock.unlock() }
            return retryAfter
        }
        func result() -> (Data, Int?, Error?) {
            lock.lock(); defer { lock.unlock() }
            return (body, status, error)
        }
    }
}
#endif
