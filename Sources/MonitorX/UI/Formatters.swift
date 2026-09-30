import Foundation

enum Fmt {
    static func bytes(_ b: UInt64) -> String { bytes(Double(b)) }

    static func bytes(_ b: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = max(0, b), i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        if i == 0 { return "\(Int(v)) B" }
        return String(format: v < 10 ? "%.2f %@" : (v < 100 ? "%.1f %@" : "%.0f %@"), v, units[i])
    }

    static func rate(_ bps: Double) -> String {
        if bps < 1 { return "0 KB/s" }
        if bps < 1024 { return "\(Int(bps)) B/s" }
        return bytes(bps) + "/s"
    }

    /// Ultra-compact for the menu bar: "1.2M", "340K", "0K".
    static func rateCompact(_ bps: Double) -> String {
        let units = ["B", "K", "M", "G"]
        var v = max(0, bps), i = 0
        while v >= 1000, i < units.count - 1 { v /= 1024; i += 1 }
        if i == 0 { return bps < 1 ? "0B" : "\(Int(bps))B" }
        return v < 10 ? String(format: "%.1f%@", v, units[i]) : String(format: "%.0f%@", v, units[i])
    }

    static func percent(_ f: Double, digits: Int = 0) -> String {
        String(format: "%.\(digits)f%%", f * 100)
    }

    static func cpuPercent(_ p: Double) -> String {
        p >= 100 ? String(format: "%.0f%%", p) : String(format: "%.1f%%", p)
    }

    static func uptime(since date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        let d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60
        if d > 0 { return "\(d) 天 \(h) 小时" }
        if h > 0 { return "\(h) 小时 \(m) 分钟" }
        return "\(m) 分钟"
    }

    static func minutes(_ m: Int) -> String {
        m >= 60 ? "\(m / 60) 小时 \(m % 60) 分钟" : "\(m) 分钟"
    }

    static func temp(_ c: Double) -> String { String(format: "%.0f°C", c) }
}
