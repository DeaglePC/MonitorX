import SwiftUI

/// "Who is using the most?" — ranked list of apps (helpers merged) or raw processes, expandable to members.
struct ProcessRankSection: View {
    let metric: ProcMetric
    let accent: Color

    @Environment(SystemMonitor.self) private var monitor
    @Environment(Settings.self) private var settings
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var expanded: Set<String> = []
    @State private var showAll = false

    private var floorValue: Double {
        switch metric {
        case .cpu: 100
        case .memory: 512 * 1024 * 1024
        case .network: 100 * 1024
        case .disk: 1024 * 1024
        }
    }

    private var title: String {
        switch metric {
        case .cpu: L("Top CPU Usage")
        case .memory: L("Top Memory Usage")
        case .network: L("Top Network Traffic")
        case .disk: L("Top Disk Activity")
        }
    }

    var body: some View {
        @Bindable var settings = settings
        let rows = monitor.top(metric, grouped: settings.groupByApp, limit: showAll ? 40 : 8)
        let denom = max(rows.first?.value(metric) ?? 0, floorValue)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                if isSnapshot {
                    Text(settings.groupByApp ? L("Apps") : L("Processes"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.07), in: .capsule)
                } else {
                    Picker("", selection: $settings.groupByApp) {
                        Text(L("Apps")).tag(true)
                        Text(L("Processes")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .tint(accent)
                    .frame(width: 104)
                }
            }

            if !monitor.processesReady {
                HStack(spacing: 8) {
                    if !isSnapshot { ProgressView().controlSize(.small) }
                    Text(L("Collecting process data…")).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else if rows.isEmpty {
                Text(metric == .network ? L("No processes using the network") : L("No activity"))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 4) {
                    ForEach(rows) { g in
                        ProcessRow(group: g, metric: metric, accent: accent, denom: denom,
                                   totalMem: monitor.mem.total,
                                   isExpanded: expanded.contains(g.id)) {
                            withAnimation(.snappy(duration: 0.25)) {
                                if expanded.contains(g.id) { expanded.remove(g.id) } else { expanded.insert(g.id) }
                            }
                        }
                    }
                }
                if !isSnapshot, monitor.top(metric, grouped: settings.groupByApp, limit: 9).count > 8 {
                    Button(showAll ? L("Show Less") : L("Show More")) { withAnimation(.snappy) { showAll.toggle() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
            }
        }
        .glassCard()
    }
}

private struct ProcessRow: View {
    let group: ProcessGroup
    let metric: ProcMetric
    let accent: Color
    let denom: Double
    let totalMem: UInt64
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        let value = group.value(metric)
        let sev = Theme.severity(metric, value: value, totalMem: totalMem)
        let color = Theme.heat(sev, base: accent)
        let canExpand = group.members.count > 1

        VStack(spacing: 0) {
            Button(action: { if canExpand { toggle() } }) {
                HStack(spacing: 10) {
                    AppIconView(appPath: group.appPath, size: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(group.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            if canExpand {
                                Text("×\(group.members.count)")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.08), in: .capsule)
                                    .foregroundStyle(.secondary)
                            } else if let pid = group.members.first?.pid {
                                Text("PID \(pid)").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 4)
                            valueView(group, tint: sev >= 0.65 ? color : nil)
                        }
                        HeatBar(fraction: value / denom, color: color)
                    }
                    if canExpand {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.members.sorted { $0.value(metric) > $1.value(metric) }.prefix(10)) { p in
                        HStack {
                            Text(p.name).lineLimit(1)
                            Text("PID \(p.pid)").foregroundStyle(.tertiary)
                            Spacer()
                            valueView(ProcessGroup(id: "\(p.pid)", name: p.name, appPath: nil, members: [p]), tint: nil, small: true)
                        }
                        .font(.system(size: 11))
                        .padding(.vertical, 3)
                    }
                    if group.members.count > 10 {
                        Text(L("%@ more processes", "\(group.members.count - 10)"))
                            .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                    }
                }
                .padding(.leading, 38)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func valueView(_ g: ProcessGroup, tint: Color?, small: Bool = false) -> some View {
        let size: CGFloat = small ? 11 : 12
        switch metric {
        case .cpu:
            Text(Fmt.cpuPercent(g.cpu)).font(.system(size: size, weight: .semibold)).monospacedDigit().foregroundStyle(tint ?? .primary)
        case .memory:
            Text(Fmt.bytes(g.mem)).font(.system(size: size, weight: .semibold)).monospacedDigit().foregroundStyle(tint ?? .primary)
        case .network:
            HStack(spacing: 8) {
                Text("↓ " + Fmt.rateCompact(g.netIn) + "/s").foregroundStyle(Theme.down)
                Text("↑ " + Fmt.rateCompact(g.netOut) + "/s").foregroundStyle(Theme.up)
            }
            .font(.system(size: size - 0.5, weight: .semibold, design: .monospaced))
        case .disk:
            HStack(spacing: 8) {
                Text(L("R %@", Fmt.rateCompact(g.diskRead))).foregroundStyle(Theme.disk)
                Text(L("W %@", Fmt.rateCompact(g.diskWrite))).foregroundStyle(Theme.disk2)
            }
            .font(.system(size: size - 0.5, weight: .semibold, design: .monospaced))
        }
    }
}

struct HeatBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: 5)
    }
}
