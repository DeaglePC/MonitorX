import SwiftUI

private let pageInsets = EdgeInsets(top: 18, leading: 16, bottom: 12, trailing: 16)

// MARK: - CPU

struct CPUView: View {
    @Environment(SystemMonitor.self) private var m

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: L("CPU"), symbol: Tab.cpu.symbol, colors: Tab.cpu.colors,
                           subtitle: L("%1$@ cores · %2$@ threads", "\(m.hardware.physicalCores)", "\(m.hardware.logicalCores)") + " · " + m.hardware.shortChip)

                HStack(spacing: 18) {
                    ZStack {
                        RingGauge(value: m.cpu.total, colors: Tab.cpu.colors, lineWidth: 10)
                        VStack(spacing: 0) {
                            Text(Fmt.percent(m.cpu.total))
                                .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                            Text(L("Total")).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 108, height: 108)

                    VStack(spacing: 9) {
                        StatDot(color: Theme.cpu, label: L("User"), value: Fmt.percent(m.cpu.user, digits: 1))
                        StatDot(color: Theme.cpu2, label: L("System"), value: Fmt.percent(m.cpu.system, digits: 1))
                        StatDot(color: .gray.opacity(0.5), label: L("Idle"), value: Fmt.percent(max(0, 1 - m.cpu.total), digits: 1))
                        Divider().opacity(0.5)
                        StatDot(color: .clear, label: L("Load 1/5/15m"),
                                value: String(format: "%.2f  %.2f  %.2f", m.cpu.load.0, m.cpu.load.1, m.cpu.load.2))
                        if let t = m.sensors.cpuTemp {
                            StatDot(color: .clear, label: L("Temperature"), value: Fmt.temp(t))
                        }
                    }
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle(L("Usage History"), trailing: L("Last 2 min"))
                    AreaChart(series: [ChartSeries(values: m.cpuHistory, color: Theme.cpu)], maxValue: 1)
                        .frame(height: 84)
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle(L("Per Core"), trailing: L("%@ threads", "\(m.cpu.perCore.count)"))
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array(m.cpu.perCore.enumerated()), id: \.offset) { i, v in
                            VStack(spacing: 4) {
                                ZStack(alignment: .bottom) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule()
                                        .fill(LinearGradient(colors: v > 0.85 ? [.orange, Color(red: 1, green: 0.27, blue: 0.23)] : [Theme.cpu2, Theme.cpu], startPoint: .top, endPoint: .bottom))
                                        .frame(height: max(4, 54 * v))
                                }
                                .frame(height: 54)
                                Text("\(i + 1)").font(.system(size: 8.5)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .glassCard()

                if Edition.hasProcessDetail { ProcessRankSection(metric: .cpu, accent: Theme.cpu) }
            }
            .padding(pageInsets)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Memory

struct MemoryView: View {
    @Environment(SystemMonitor.self) private var m

    private var pressure: (String, Color) {
        switch m.mem.pressure {
        case 4: (L("Critical"), .red)
        case 2: (L("Warning"), .orange)
        default: (L("Normal"), Theme.down)
        }
    }

    var body: some View {
        let mem = m.mem
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: L("Memory"), symbol: Tab.memory.symbol, colors: Tab.memory.colors,
                           subtitle: L("Physical memory %@", Fmt.bytes(mem.total)))

                HStack(spacing: 18) {
                    ZStack {
                        RingGauge(value: mem.usedFraction, colors: Tab.memory.colors, lineWidth: 10)
                        VStack(spacing: 0) {
                            Text(Fmt.percent(mem.usedFraction))
                                .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                            Text(L("Used")).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 108, height: 108)

                    VStack(alignment: .leading, spacing: 9) {
                        Text(Fmt.bytes(mem.used)).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(L("of %@", Fmt.bytes(mem.total))).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Circle().fill(pressure.1).frame(width: 8, height: 8)
                            Text(L("Memory pressure · %@", pressure.0)).font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(pressure.1.opacity(0.15), in: .capsule)
                        if mem.swapTotal > 0 {
                            Text(L("Swap %1$@ / %2$@", Fmt.bytes(mem.swapUsed), Fmt.bytes(mem.swapTotal)))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(L("Memory Breakdown"), trailing: nil)
                    StackedBar(segments: [
                        .init(value: Double(mem.app), color: Theme.mem),
                        .init(value: Double(mem.wired), color: Theme.mem2),
                        .init(value: Double(mem.compressed), color: Theme.disk),
                        .init(value: Double(mem.cached), color: Theme.cpu2),
                        .init(value: Double(mem.free), color: .gray.opacity(0.35)),
                    ])
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())], spacing: 8) {
                        StatDot(color: Theme.mem, label: L("App Memory"), value: Fmt.bytes(mem.app))
                        StatDot(color: Theme.mem2, label: L("Wired Memory"), value: Fmt.bytes(mem.wired))
                        StatDot(color: Theme.disk, label: L("Compressed"), value: Fmt.bytes(mem.compressed))
                        StatDot(color: Theme.cpu2, label: L("Cached Files"), value: Fmt.bytes(mem.cached))
                        StatDot(color: .gray.opacity(0.5), label: L("Free"), value: Fmt.bytes(mem.free))
                    }
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle(L("Usage History"), trailing: L("Last 2 min"))
                    AreaChart(series: [ChartSeries(values: m.memHistory, color: Theme.mem)], maxValue: 1)
                        .frame(height: 76)
                }
                .glassCard()

                if Edition.hasProcessDetail { ProcessRankSection(metric: .memory, accent: Theme.mem) }
            }
            .padding(pageInsets)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Network

struct NetworkView: View {
    @Environment(SystemMonitor.self) private var m

    var body: some View {
        let net = m.net
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: L("Network"), symbol: Tab.network.symbol, colors: Tab.network.colors,
                           subtitle: net.interface == "—" ? L("Not connected") : "\(net.interface) · \(net.ip)")

                HStack(spacing: 10) {
                    speedBlock(symbol: "arrow.down.circle.fill", title: L("Download"), rate: net.downRate, colors: [Theme.down2, Theme.down], total: net.totalDown)
                    speedBlock(symbol: "arrow.up.circle.fill", title: L("Upload"), rate: net.upRate, colors: [Theme.up, Color(red: 0.3, green: 0.5, blue: 1)], total: net.totalUp)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        sectionTitle(L("Live Traffic"), trailing: nil)
                        Spacer()
                        legend(Theme.down, L("Download")); legend(Theme.up, L("Upload"))
                    }
                    AreaChart(series: [ChartSeries(values: m.netDownHistory, color: Theme.down),
                                       ChartSeries(values: m.netUpHistory, color: Theme.up)],
                              minCeiling: 100 * 1024)
                        .frame(height: 96)
                }
                .glassCard()

                if Edition.hasProcessDetail { ProcessRankSection(metric: .network, accent: Theme.down) }
            }
            .padding(pageInsets)
        }
        .scrollIndicators(.hidden)
    }

    private func speedBlock(symbol: String, title: String, rate: Double, colors: [Color], total: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(colors[1])
                Text(title).foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .semibold))
            Text(Fmt.rate(rate))
                .font(.system(size: 21, weight: .bold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(L("Total this session: %@", Fmt.bytes(total))).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: colors[1])
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(t).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Disk

struct DiskView: View {
    @Environment(SystemMonitor.self) private var m

    var body: some View {
        let disk = m.disk
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: L("Disk"), symbol: Tab.disk.symbol, colors: Tab.disk.colors,
                           subtitle: L("%@ local volumes", "\(disk.volumes.count)"))

                ForEach(disk.volumes) { v in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: v.isInternal ? "internaldrive.fill" : "externaldrive.fill").foregroundStyle(Theme.disk)
                            Text(v.name).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text(Fmt.percent(v.usedFraction)).font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                        }
                        StackedBar(segments: [
                            .init(value: Double(v.used), color: Theme.heat(v.usedFraction > 0.9 ? 1 : (v.usedFraction > 0.8 ? 0.5 : 0), base: Theme.disk)),
                            .init(value: Double(v.free), color: .clear),
                        ], height: 12)
                        HStack {
                            Text(L("Used: %@", Fmt.bytes(v.used)))
                            Spacer()
                            Text(L("Available: %@", Fmt.bytes(v.free)))
                            Text("· " + L("Total: %@", Fmt.bytes(v.total))).foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .glassCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sectionTitle(L("Disk Throughput"), trailing: nil)
                        Spacer()
                        Group {
                            HStack(spacing: 4) { Circle().fill(Theme.disk).frame(width: 6, height: 6); Text(L("Read %@", Fmt.rate(disk.readRate))) }
                            HStack(spacing: 4) { Circle().fill(Theme.disk2).frame(width: 6, height: 6); Text(L("Write %@", Fmt.rate(disk.writeRate))) }
                        }
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    AreaChart(series: [ChartSeries(values: m.diskReadHistory, color: Theme.disk),
                                       ChartSeries(values: m.diskWriteHistory, color: Theme.disk2)],
                              minCeiling: 1024 * 1024)
                        .frame(height: 84)
                }
                .glassCard()

                if Edition.hasProcessDetail { ProcessRankSection(metric: .disk, accent: Theme.disk) }
            }
            .padding(pageInsets)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Hardware

struct HardwareView: View {
    @Environment(SystemMonitor.self) private var m

    var body: some View {
        let h = m.hardware
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: L("Hardware"), symbol: Tab.hardware.symbol, colors: Tab.hardware.colors, subtitle: h.modelID)

                group("Mac", symbol: "desktopcomputer") {
                    InfoRow(key: L("Model"), value: h.modelName)
                    InfoRow(key: L("Model Identifier"), value: h.modelID)
                    if !h.serial.isEmpty { InfoRow(key: L("Serial Number"), value: h.serial, copyable: true) }
                    InfoRow(key: L("Operating System"), value: h.osVersion)
                    InfoRow(key: L("Uptime"), value: Fmt.uptime(since: h.bootDate))
                }

                group(L("Processor & Memory"), symbol: "cpu") {
                    InfoRow(key: L("Chip"), value: h.shortChip)
                    InfoRow(key: L("Architecture"), value: h.arch)
                    InfoRow(key: L("Cores"), value: L("%1$@ cores / %2$@ threads", "\(h.physicalCores)", "\(h.logicalCores)"))
                    InfoRow(key: L("Memory"), value: Fmt.bytes(h.memory))
                    if let t = m.sensors.cpuTemp { InfoRow(key: L("CPU Temperature"), value: Fmt.temp(t)) }
                }

                if !h.gpu.isEmpty || !h.displays.isEmpty {
                    group(L("Graphics & Displays"), symbol: "display") {
                        if !h.gpu.isEmpty { InfoRow(key: L("Graphics"), value: h.gpu) }
                        ForEach(h.displays, id: \.self) { InfoRow(key: L("Display"), value: $0) }
                        if let t = m.sensors.gpuTemp { InfoRow(key: L("GPU Temperature"), value: Fmt.temp(t)) }
                    }
                }

                if let b = m.battery {
                    group(L("Battery"), symbol: "battery.100percent") {
                        InfoRow(key: L("Charge"), value: "\(b.percent)%" + (b.isCharging ? " · " + L("Charging") : (b.onAC ? " · " + L("Power Adapter") : "")))
                        if let mins = b.minutesRemaining { InfoRow(key: b.isCharging ? L("Time to Full") : L("Time Remaining"), value: Fmt.minutes(mins)) }
                        if let hp = b.health { InfoRow(key: L("Maximum Capacity"), value: Fmt.percent(hp)) }
                        if let c = b.cycles { InfoRow(key: L("Cycle Count"), value: "\(c)") }
                        if let t = b.temperature { InfoRow(key: L("Battery Temperature"), value: String(format: "%.1f°C", t)) }
                    }
                }

                if !m.sensors.fans.isEmpty {
                    group(L("Cooling"), symbol: "fan") {
                        ForEach(m.sensors.fans) { fan in
                            InfoRow(key: fan.name, value: L("%1$@ RPM (%2$@ – %3$@)", "\(Int(fan.rpm))", "\(Int(fan.min))", "\(Int(fan.max))"))
                        }
                    }
                }
            }
            .padding(pageInsets)
        }
        .scrollIndicators(.hidden)
    }

    private func group<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(Theme.hw)
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

// MARK: - shared

func sectionTitle(_ title: String, trailing: String?) -> some View {
    HStack {
        Text(title).font(.system(size: 14, weight: .semibold))
        Spacer()
        if let trailing { Text(trailing).font(.system(size: 10.5)).foregroundStyle(.secondary) }
    }
}
