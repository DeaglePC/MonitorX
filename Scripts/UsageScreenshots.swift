import SwiftUI
import AppKit

/// Renders the production quota cards with in-memory demo readings. Never changes local account data.
@main
struct UsageScreenshots {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        Localizer.shared.language = .zhHans
        let now = Date()
        let codex = CodexUsageMonitor()
        codex.buckets = [.init(limitId: "codex", limitName: nil,
            primary: .init(usedPercent: 18, windowDurationMins: 300, resetsAt: now.timeIntervalSince1970 + 7200),
            secondary: .init(usedPercent: 36, windowDurationMins: 10080, resetsAt: now.timeIntervalSince1970 + 4 * 86400))]
        codex.updatedAt = now
        let claude = ClaudeUsageMonitor()
        claude.isConnected = true
        claude.setupStatus = .signedIn
        claude.snapshot = .init(updatedAt: now.timeIntervalSince1970, windows: [
            "five_hour": .init(used_percentage: 25, resets_at: now.timeIntervalSince1970 + 10800),
            "seven_day": .init(used_percentage: 48, resets_at: now.timeIntervalSince1970 + 5 * 86400)])
        for (name, scheme) in [("dark", ColorScheme.dark), ("light", ColorScheme.light)] {
            let view = VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .foregroundStyle(.white).font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Theme.cpu.gradient, in: .rect(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MonitorX").font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("额度概览 · 演示数据").font(.caption).foregroundStyle(.secondary)
                    }
                }
                CodexUsageCard(usage: codex)
                ClaudeUsageCard(usage: claude)
                Text("真实 App 界面渲染 · 以上额度为示例数值")
                    .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            .padding(20).frame(width: 420)
            .background(scheme == .dark ? Color(white: 0.10) : Color(white: 0.955))
            .environment(\.isSnapshot, true).environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cgImage = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            for folder in ["docs/images", "website/images"] {
                try data.write(to: URL(fileURLWithPath: "\(folder)/ai-usage-\(name).png"), options: .atomic)
            }
            print("Rendered ai-usage-\(name).png: \(cgImage.width) × \(cgImage.height), demo data")
        }
    }
}
