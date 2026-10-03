import SwiftUI

struct OverviewView: View {
    var go: (Tab) -> Void
    @Environment(SystemMonitor.self) private var m

    var body: some View {
        PageScroll {
            VStack(spacing: 14) {
                header
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    cpuCard
                    memCard
                    netCard
                    diskCard
                }
                sensorRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(LinearGradient(colors: Tab.overview.colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 13))
                .shadow(color: Theme.cpu.opacity(0.4), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.hardware.modelName).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(m.hardware.shortChip + " · " + L("Up %@", Fmt.uptime(since: m.hardware.bootDate)))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.trailing, headerTrailingRoom)
    }

    // MARK: cards

    private var cpuCard: some View {
        MetricCard(tab: .cpu, value: Fmt.percent(m.cpu.total), caption: L("%1$@ threads · Load %2$@", "\(m.cpu.perCore.count)", String(format: "%.2f", m.cpu.load.0)),
                   ring: m.cpu.total, series: [ChartSeries(values: m.cpuHistory, color: Theme.cpu)], maxValue: 1,
                   top: m.topOne(.cpu), topText: { Fmt.cpuPercent($0.cpu) }, onTap: { go(.cpu) })
    }

    private var memCard: some View {
        MetricCard(tab: .memory, value: Fmt.percent(m.mem.usedFraction), caption: "\(Fmt.bytes(m.mem.used)) / \(Fmt.bytes(m.mem.total))",
                   ring: m.mem.usedFraction, series: [ChartSeries(values: m.memHistory, color: Theme.mem)], maxValue: 1,
                   top: m.topOne(.memory), topText: { Fmt.bytes($0.mem) }, onTap: { go(.memory) })
    }

    private var netCard: some View {
        MetricCard(tab: .network, value: "↓ " + Fmt.rateCompact(m.net.downRate), caption: L("↑ %@/s upload", Fmt.rateCompact(m.net.upRate)),
                   ring: nil,
                   series: [ChartSeries(values: m.netDownHistory, color: Theme.down), ChartSeries(values: m.netUpHistory, color: Theme.up)],
                   maxValue: nil, minCeiling: 100 * 1024,
                   top: m.topOne(.network), topText: { "↓" + Fmt.rateCompact($0.netIn) + " ↑" + Fmt.rateCompact($0.netOut) }, onTap: { go(.network) })
    }

    private var diskCard: some View {
        MetricCard(tab: .disk, value: Fmt.percent(m.disk.primaryUsed), caption: L("R %1$@ · W %2$@", Fmt.rateCompact(m.disk.readRate), Fmt.rateCompact(m.disk.writeRate)),
                   ring: m.disk.primaryUsed,
                   series: [ChartSeries(values: m.diskReadHistory, color: Theme.disk), ChartSeries(values: m.diskWriteHistory, color: Theme.disk2)],
                   maxValue: nil, minCeiling: 1024 * 1024,
                   top: m.topOne(.disk), topText: { Fmt.rateCompact($0.diskRead + $0.diskWrite) + "/s" }, onTap: { go(.disk) })
    }

    // MARK: battery / sensors

    private var sensorRow: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let b = m.battery {
                    tile(symbol: batterySymbol(b), color: b.percent <= 20 && !b.onAC ? .red : Theme.down,
                         title: L("Battery"), value: "\(b.percent)%", detail: b.isCharging ? L("Charging") : (b.onAC ? L("Power Adapter") : L("On Battery")))
                }
                if let t = m.sensors.cpuTemp {
                    tile(symbol: "thermometer.medium", color: t > 85 ? .red : (t > 70 ? .orange : Theme.disk2),
                         title: L("CPU Temperature"), value: Fmt.temp(t), detail: t > 85 ? L("High") : L("Normal"))
                }
                if let rpm = m.sensors.fans.map(\.rpm).max() {
                    tile(symbol: "fan.fill", color: Theme.cpu2, title: L("Fan"), value: "\(Int(rpm))", detail: "RPM")
                }
            }
        }
        .onTapGesture { go(Edition.hasSensors ? .sensors : .hardware) }
    }

    private func tile(symbol: String, color: Color, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(title).foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            Text(value).font(.system(size: 19, weight: .bold, design: .rounded)).monospacedDigit()
            Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassSurface(radius: 18)
    }

    private func batterySymbol(_ b: BatteryInfo) -> String {
        if b.isCharging { return "battery.100percent.bolt" }
        switch b.percent {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

private struct MetricCard: View {
    let tab: Tab
    let value: String
    let caption: String
    let ring: Double?
    let series: [ChartSeries]
    var maxValue: Double?
    var minCeiling: Double = 1
    let top: ProcessGroup?
    let topText: (ProcessGroup) -> String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: tab.symbol).foregroundStyle(tab.accent)
                    Text(tab.title).foregroundStyle(.secondary)
                    Spacer()
                    if let ring {
                        RingGauge(value: ring, colors: tab.colors, lineWidth: 4).frame(width: 20, height: 20)
                    }
                }
                .font(.system(size: 12, weight: .semibold))

                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Text(caption).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }

                AreaChart(series: series, maxValue: maxValue, minCeiling: minCeiling, grid: false)
                    .frame(height: 34)

                if Edition.hasProcessDetail {
                Divider().opacity(0.5)

                HStack(spacing: 6) {
                    if let top {
                        AppIconView(appPath: top.appPath, size: 16)
                        Text(top.name).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(topText(top)).fontWeight(.semibold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        Image(systemName: "sparkle.magnifyingglass").foregroundStyle(.tertiary)
                        Text(L("Collecting…")).foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
                .font(.system(size: 11))
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(radius: 22, tint: tab.accent, tintOpacity: 0.10, interactive: true)
        }
        .buttonStyle(.plain)
    }
}
