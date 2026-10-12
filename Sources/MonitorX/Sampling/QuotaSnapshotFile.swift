import AppKit
import UniformTypeIdentifiers

/// Quota-only interchange format. Never import a credential file as a quota snapshot.
enum QuotaSnapshotFile {
    struct Codex: Codable {
        let provider: String
        let updatedAt: Double
        let buckets: [CodexLimitBucket]
    }
    enum Invalid: Error { case snapshot }

    static func object(_ data: Data, keys: Set<String>) throws -> [String: Any] {
        guard data.count <= 64 * 1024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys).isSubset(of: keys),
              let timestamp = root["updatedAt"] as? Double,
              timestamp.isFinite, timestamp > 0,
              timestamp <= Date().timeIntervalSince1970 + 300 else { throw Invalid.snapshot }
        return root
    }

    static func validateWindow(_ window: [String: Any], percentage: String, reset: String, duration: String? = nil) throws {
        let keys = Set([percentage, reset] + (duration.map { [$0] } ?? []))
        guard Set(window.keys).isSubset(of: keys),
              let used = window[percentage] as? Double, used.isFinite, (0...100).contains(used),
              let resets = window[reset] as? Double, resets.isFinite, resets > 0 else { throw Invalid.snapshot }
        if let duration {
            guard let minutes = window[duration] as? Int, (1...525600).contains(minutes) else { throw Invalid.snapshot }
        }
    }

    static func codex(_ data: Data) throws -> Codex {
        let root = try object(data, keys: ["provider", "updatedAt", "buckets"])
        guard root["provider"] as? String == "codex",
              let buckets = root["buckets"] as? [[String: Any]], !buckets.isEmpty, buckets.count <= 32 else { throw Invalid.snapshot }
        for bucket in buckets {
            guard Set(bucket.keys).isSubset(of: ["limitId", "limitName", "primary", "secondary"]) else { throw Invalid.snapshot }
            for key in ["limitId", "limitName"] {
                if let value = bucket[key], !(value is NSNull) {
                    guard let name = value as? String, name.count <= 100,
                          !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Invalid.snapshot }
                }
            }
            var count = 0
            for key in ["primary", "secondary"] {
                if let value = bucket[key], !(value is NSNull) {
                    guard let window = value as? [String: Any] else { throw Invalid.snapshot }
                    try validateWindow(window, percentage: "usedPercent", reset: "resetsAt", duration: "windowDurationMins")
                    count += 1
                }
            }
            guard count > 0 else { throw Invalid.snapshot }
        }
        return try JSONDecoder().decode(Codex.self, from: data)
    }

    static func claude(_ data: Data) throws -> ClaudeQuotaSnapshot {
        let root = try object(data, keys: ["updatedAt", "windows"])
        guard let windows = root["windows"] as? [String: [String: Any]], !windows.isEmpty,
              Set(windows.keys).isSubset(of: ["five_hour", "seven_day"]) else { throw Invalid.snapshot }
        for window in windows.values {
            try validateWindow(window, percentage: "used_percentage", reset: "resets_at")
        }
        return try JSONDecoder().decode(ClaudeQuotaSnapshot.self, from: data)
    }
}

#if APPSTORE
/// Only an NSOpenPanel grant can establish access. No home-directory scanning or external processes.
final class QuotaFileAccess {
    let provider: String
    private let defaults: UserDefaults
    private var key: String { "quotaSnapshotBookmark." + provider }
    var isConnected: Bool { defaults.data(forKey: key) != nil }

    init(provider: String, defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
    }

    private func validate(_ data: Data) throws {
        if provider == "codex" { _ = try QuotaSnapshotFile.codex(data) }
        else { _ = try QuotaSnapshotFile.claude(data) }
    }

    func choose() -> Bool {
        let alert = NSAlert()
        alert.messageText = L("Connect quota file")
        alert.informativeText = L("Choose a quota-only JSON snapshot. MonitorX will read this file until you disconnect. Do not select login credentials. This does not query your account online.")
        alert.addButton(withTitle: L("Choose File"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        let panel = NSOpenPanel()
        panel.title = L("Connect quota file")
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            try validate(Self.readBounded(url))
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: key)
            return true
        } catch {
            let failure = NSAlert()
            failure.messageText = L("Couldn't read quota file. Select a valid quota snapshot again.")
            failure.runModal()
            return false
        }
    }

    func read() throws -> Data {
        guard let bookmark = defaults.data(forKey: key) else { throw QuotaSnapshotFile.Invalid.snapshot }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, url.startAccessingSecurityScopedResource() else { throw QuotaSnapshotFile.Invalid.snapshot }
        defer { url.stopAccessingSecurityScopedResource() }
        let data = try Self.readBounded(url)
        try validate(data)
        return data
    }

    private static func readBounded(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 64 * 1024 + 1) ?? Data()
        guard data.count <= 64 * 1024 else { throw QuotaSnapshotFile.Invalid.snapshot }
        return data
    }

    func disconnect() { defaults.removeObject(forKey: key) }
}
#endif
