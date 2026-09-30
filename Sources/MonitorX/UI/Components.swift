import SwiftUI
import AppKit

// MARK: - Theme

enum Theme {
    static let cpu = Color(red: 0.25, green: 0.52, blue: 1.00)
    static let cpu2 = Color(red: 0.35, green: 0.85, blue: 1.00)
    static let mem = Color(red: 0.68, green: 0.36, blue: 1.00)
    static let mem2 = Color(red: 1.00, green: 0.42, blue: 0.72)
    static let down = Color(red: 0.16, green: 0.82, blue: 0.52)
    static let down2 = Color(red: 0.45, green: 0.95, blue: 0.75)
    static let up = Color(red: 0.20, green: 0.75, blue: 1.00)
    static let disk = Color(red: 1.00, green: 0.58, blue: 0.18)
    static let disk2 = Color(red: 1.00, green: 0.82, blue: 0.25)
    static let temp = Color(red: 0.98, green: 0.32, blue: 0.38)
    static let temp2 = Color(red: 1.00, green: 0.58, blue: 0.42)
    static let hw = Color(red: 0.42, green: 0.45, blue: 1.00)
    static let hw2 = Color(red: 0.65, green: 0.60, blue: 1.00)

    /// Bars stay calm until a process gets heavy, then warm up so hot spots pop out.
    static func heat(_ severity: Double, base: Color) -> Color {
        switch severity {
        case ..<0.35: return base
        case ..<0.65: return .yellow
        case ..<1.0: return .orange
        default: return Color(red: 1, green: 0.27, blue: 0.23)
        }
    }

    static func severity(_ metric: ProcMetric, value: Double, totalMem: UInt64) -> Double {
        switch metric {
        case .cpu: return value / 100
        case .memory: return value / (Double(max(totalMem, 1)) * 0.20)
        case .network: return value / (10 * 1024 * 1024)
        case .disk: return value / (50 * 1024 * 1024)
        }
    }
}

enum Tab: String, CaseIterable, Identifiable {
    case overview, cpu, memory, network, disk, sensors, hardware
    var id: String { rawValue }

    /// Tabs offered by this edition (the sandboxed App Store build has no sensor page).
    static var available: [Tab] { allCases.filter { $0 != .sensors || Edition.hasSensors } }

    var title: String {
        switch self {
        case .overview: "概览"
        case .cpu: "CPU"
        case .memory: "内存"
        case .network: "网络"
        case .disk: "磁盘"
        case .sensors: "传感器"
        case .hardware: "硬件"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .cpu: "cpu.fill"
        case .memory: "memorychip.fill"
        case .network: "arrow.up.arrow.down.circle.fill"
        case .disk: "internaldrive.fill"
        case .sensors: "thermometer.medium"
        case .hardware: "laptopcomputer"
        }
    }

    var colors: [Color] {
        switch self {
        case .overview: [Theme.hw2, Theme.cpu]
        case .cpu: [Theme.cpu2, Theme.cpu]
        case .memory: [Theme.mem2, Theme.mem]
        case .network: [Theme.down2, Theme.down]
        case .disk: [Theme.disk2, Theme.disk]
        case .sensors: [Theme.temp2, Theme.temp]
        case .hardware: [Theme.hw2, Theme.hw]
        }
    }

    var accent: Color { colors[1] }
}

// MARK: - Glass helpers

extension View {
    func glassCard(radius: CGFloat = 22, padding: CGFloat = 14, tint: Color? = nil) -> some View {
        self.padding(padding)
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.14)) } ?? Glass.regular,
                         in: .rect(cornerRadius: radius))
    }
}

// MARK: - Page header

struct PageHeader: View {
    let title: String
    let symbol: String
    let colors: [Color]
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 12))
                .shadow(color: colors.last!.opacity(0.4), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.trailing, 44)   // room for the settings button
    }
}

// MARK: - Gauges & charts

struct RingGauge: View {
    var value: Double
    var colors: [Color]
    var lineWidth: CGFloat = 9

    var body: some View {
        let v = max(0.0, min(1.0, value))
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(v, 0.004))
                .stroke(AngularGradient(colors: colors + [colors.first!], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct ChartSeries {
    var values: [Double]
    var color: Color
}

struct AreaChart: View {
    var series: [ChartSeries]
    var maxValue: Double?
    var minCeiling: Double = 1
    var grid = true
    var capacity = SystemMonitor.historyCapacity

    var body: some View {
        let ceiling = maxValue ?? max(minCeiling, (series.flatMap(\.values).max() ?? 0) * 1.25)
        Canvas { ctx, size in
            if grid {
                for k in 1..<4 {
                    var p = Path()
                    let y = size.height * CGFloat(k) / 4
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(.primary.opacity(0.07)), style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                }
            }
            for s in series where s.values.count >= 2 {
                let n = s.values.count
                func point(_ i: Int) -> CGPoint {
                    let x = size.width * CGFloat(capacity - n + i) / CGFloat(capacity - 1)
                    let y = size.height * (1 - CGFloat(min(1, s.values[i] / ceiling)))
                    return CGPoint(x: x, y: min(max(y, 1), size.height - 1))
                }
                var line = Path()
                line.move(to: point(0))
                for i in 1..<n { line.addLine(to: point(i)) }
                var area = line
                area.addLine(to: CGPoint(x: point(n - 1).x, y: size.height))
                area.addLine(to: CGPoint(x: point(0).x, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(Gradient(colors: [s.color.opacity(0.38), s.color.opacity(0.02)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                ctx.stroke(line, with: .color(s.color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct StackedBar: View {
    struct Segment: Identifiable { let id = UUID(); var value: Double; var color: Color }
    var segments: [Segment]
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let total = max(segments.reduce(0) { $0 + $1.value }, 1)
            let usable = geo.size.width - CGFloat(max(0, segments.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(segments) { s in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(s.color.gradient)
                        .frame(width: max(0, usable * CGFloat(s.value / total)))
                }
            }
        }
        .frame(height: height)
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 5))
    }
}

struct StatDot: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color.gradient).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).fontWeight(.medium).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

struct InfoRow: View {
    let key: String
    let value: String
    var copyable = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(copied ? "已复制" : value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .foregroundStyle(copied ? Theme.down : .primary)
                .onTapGesture {
                    guard copyable else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
        }
        .font(.system(size: 12.5))
    }
}

// MARK: - App icons

@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]
    private static let generic: NSImage = {
        NSWorkspace.shared.icon(for: .unixExecutable)
    }()

    static func icon(for appPath: String?) -> NSImage {
        guard let appPath else { return generic }
        if let i = cache[appPath] { return i }
        let img = NSWorkspace.shared.icon(forFile: appPath)
        cache[appPath] = img
        return img
    }
}

struct AppIconView: View {
    let appPath: String?
    var size: CGFloat = 26

    var body: some View {
        Image(nsImage: IconCache.icon(for: appPath))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
