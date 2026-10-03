import SwiftUI

/// Every temperature sensor the SMC exposes, grouped by component, plus fan speeds.
struct SensorsView: View {
    @Environment(SystemMonitor.self) private var m
    @Environment(\.isSnapshot) private var isSnapshot

    private func severity(_ t: Double) -> Double { (t - 30) / 60 }

    var body: some View {
        let s = m.sensors
        let grouped = Dictionary(grouping: s.all, by: \.category)
        let hottest = s.all.max { $0.value < $1.value }
        let average = s.all.isEmpty ? 0 : s.all.map(\.value).reduce(0, +) / Double(s.all.count)

        PageScroll {
            VStack(spacing: 14) {
                PageHeader(title: L("Sensors"), symbol: Tab.sensors.symbol, colors: Tab.sensors.colors,
                           subtitle: L("%1$@ temperature sensors · %2$@ fans", "\(s.all.count)", "\(s.fans.count)"))

                if let hottest {
                    HStack(spacing: 10) {
                        summary(title: L("Hottest"), value: Fmt.temp(hottest.value), detail: hottest.name, sev: severity(hottest.value))
                        summary(title: L("Average"), value: Fmt.temp(average), detail: L("%@ sensors", "\(s.all.count)"), sev: severity(average))
                    }
                }

                if !s.fans.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle(L("Fans"), trailing: nil)
                        ForEach(s.fans) { fan in
                            VStack(spacing: 6) {
                                HStack {
                                    Image(systemName: "fan.fill").foregroundStyle(Theme.cpu2)
                                    Text(fan.name).font(.system(size: 12.5, weight: .medium))
                                    Spacer()
                                    Text("\(Int(fan.rpm)) RPM").font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                                }
                                HeatBar(fraction: fan.fraction, color: Theme.heat(fan.fraction * 0.7, base: Theme.cpu2))
                                HStack {
                                    Text("\(Int(fan.min))").foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(Fmt.percent(fan.fraction)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(fan.max))").foregroundStyle(.tertiary)
                                }
                                .font(.system(size: 10)).monospacedDigit()
                            }
                        }
                    }
                    .glassCard()
                }

                if s.all.isEmpty {
                    HStack(spacing: 8) {
                        if !isSnapshot { ProgressView().controlSize(.small) }
                        Text(L("Reading sensors…")).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .glassCard()
                }

                ForEach(SensorCategory.allCases, id: \.rawValue) { cat in
                    if let items = grouped[cat]?.sorted(by: { $0.value > $1.value }) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: cat.symbol).foregroundStyle(Theme.temp)
                                Text(cat.title).font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text("\(items.count)").font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                            ForEach(items) { row($0) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                    }
                }
            }
            .padding(EdgeInsets(top: 18, leading: 16, bottom: 12, trailing: 16))
        }
    }

    private func row(_ r: SensorReading) -> some View {
        let sev = severity(r.value)
        let color = Theme.heat(sev, base: Theme.down)
        return HStack(spacing: 10) {
            Text(r.name).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 6)
            HeatBar(fraction: max(0.03, min(1, sev)), color: color).frame(width: 84)
            Text(Fmt.temp(r.value))
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(sev >= 0.65 ? color : .primary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func summary(title: String, value: String, detail: String, sev: Double) -> some View {
        let color = Theme.heat(sev, base: Theme.down)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "thermometer.medium").foregroundStyle(color)
                Text(title).foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .semibold))
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
            Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: color)
    }
}
