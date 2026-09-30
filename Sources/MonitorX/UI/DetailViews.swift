import SwiftUI

private let pageInsets = EdgeInsets(top: 18, leading: 16, bottom: 12, trailing: 16)

// MARK: - CPU

struct CPUView: View {
    @Environment(SystemMonitor.self) private var m

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: "CPU", symbol: Tab.cpu.symbol, colors: Tab.cpu.colors,
                           subtitle: "\(m.hardware.physicalCores) 核 \(m.hardware.logicalCores) 线程 · " + m.hardware.shortChip)

                HStack(spacing: 18) {
                    ZStack {
                        RingGauge(value: m.cpu.total, colors: Tab.cpu.colors, lineWidth: 10)
                        VStack(spacing: 0) {
                            Text(Fmt.percent(m.cpu.total))
                                .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("总占用").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 108, height: 108)

                    VStack(spacing: 9) {
                        StatDot(color: Theme.cpu, label: "用户", value: Fmt.percent(m.cpu.user, digits: 1))
                        StatDot(color: Theme.cpu2, label: "系统", value: Fmt.percent(m.cpu.system, digits: 1))
                        StatDot(color: .gray.opacity(0.5), label: "空闲", value: Fmt.percent(max(0, 1 - m.cpu.total), digits: 1))
                        Divider().opacity(0.5)
                        StatDot(color: .clear, label: "负载 1/5/15m",
                                value: String(format: "%.2f  %.2f  %.2f", m.cpu.load.0, m.cpu.load.1, m.cpu.load.2))
                        if let t = m.sensors.cpuTemp {
                            StatDot(color: .clear, label: "温度", value: Fmt.temp(t))
                        }
                    }
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("占用趋势", trailing: "近 2 分钟")
                    AreaChart(series: [ChartSeries(values: m.cpuHistory, color: Theme.cpu)], maxValue: 1)
                        .frame(height: 84)
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("各核心", trailing: "\(m.cpu.perCore.count) 线程")
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
        case 4: ("严重", .red)
        case 2: ("警告", .orange)
        default: ("正常", Theme.down)
        }
    }

    var body: some View {
        let mem = m.mem
        ScrollView {
            VStack(spacing: 14) {
                PageHeader(title: "内存", symbol: Tab.memory.symbol, colors: Tab.memory.colors,
                           subtitle: "物理内存 \(Fmt.bytes(mem.total))")

                HStack(spacing: 18) {
                    ZStack {
                        RingGauge(value: mem.usedFraction, colors: Tab.memory.colors, lineWidth: 10)
                        VStack(spacing: 0) {
                            Text(Fmt.percent(mem.usedFraction))
                                .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("已使用").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 108, height: 108)

                    VStack(alignment: .leading, spacing: 9) {
                        Text(Fmt.bytes(mem.used)).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("共 \(Fmt.bytes(mem.total))").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Circle().fill(pressure.1).frame(width: 8, height: 8)
                            Text("内存压力 · \(pressure.0)").font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(pressure.1.opacity(0.15), in: .capsule)
                        if mem.swapTotal > 0 {
                            Text("交换 \(Fmt.bytes(mem.swapUsed)) / \(Fmt.bytes(mem.swapTotal))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("内存构成", trailing: nil)
                    StackedBar(segments: [
                        .init(value: Double(mem.app), color: Theme.mem),
                        .init(value: Double(mem.wired), color: Theme.mem2),
                        .init(value: Double(mem.compressed), color: Theme.disk),
                        .init(value: Double(mem.cached), color: Theme.cpu2),
                        .init(value: Double(mem.free), color: .gray.opacity(0.35)),
                    ])
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())], spacing: 8) {
                        StatDot(color: Theme.mem, label: "App 内存", value: Fmt.bytes(mem.app))
                        StatDot(color: Theme.mem2, label: "联动内存", value: Fmt.bytes(mem.wired))
                        StatDot(color: Theme.disk, label: "已压缩", value: Fmt.bytes(mem.compressed))
                        StatDot(color: Theme.cpu2, label: "文件缓存", value: Fmt.bytes(mem.cached))
                        StatDot(color: .gray.opacity(0.5), label: "空闲", value: Fmt.bytes(mem.free))
                    }
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("使用趋势", trailing: "近 2 分钟")
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
                PageHeader(title: "网络", symbol: Tab.network.symbol, colors: Tab.network.colors,
                           subtitle: net.interface == "—" ? "未连接" : "\(net.interface) · \(net.ip)")

                HStack(spacing: 10) {
                    speedBlock(symbol: "arrow.down.circle.fill", title: "下载", rate: net.downRate, colors: [Theme.down2, Theme.down], total: net.totalDown)
                    speedBlock(symbol: "arrow.up.circle.fill", title: "上传", rate: net.upRate, colors: [Theme.up, Color(red: 0.3, green: 0.5, blue: 1)], total: net.totalUp)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        sectionTitle("实时流量", trailing: nil)
                        Spacer()
                        legend(Theme.down, "下载"); legend(Theme.up, "上传")
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
            Text("本次运行累计 \(Fmt.bytes(total))").font(.system(size: 10.5)).foregroundStyle(.secondary)
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
                PageHeader(title: "磁盘", symbol: Tab.disk.symbol, colors: Tab.disk.colors,
                           subtitle: "\(disk.volumes.count) 个本地卷")

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
                            Text("已用 \(Fmt.bytes(v.used))")
                            Spacer()
                            Text("可用 \(Fmt.bytes(v.free))")
                            Text("· 共 \(Fmt.bytes(v.total))").foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .glassCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sectionTitle("磁盘吞吐", trailing: nil)
                        Spacer()
                        Group {
                            HStack(spacing: 4) { Circle().fill(Theme.disk).frame(width: 6, height: 6); Text("读取 \(Fmt.rate(disk.readRate))") }
                            HStack(spacing: 4) { Circle().fill(Theme.disk2).frame(width: 6, height: 6); Text("写入 \(Fmt.rate(disk.writeRate))") }
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
                PageHeader(title: "硬件", symbol: Tab.hardware.symbol, colors: Tab.hardware.colors, subtitle: h.modelID)

                group("Mac", symbol: "desktopcomputer") {
                    InfoRow(key: "机型", value: h.modelName)
                    InfoRow(key: "型号标识", value: h.modelID)
                    if !h.serial.isEmpty { InfoRow(key: "序列号", value: h.serial, copyable: true) }
                    InfoRow(key: "系统", value: h.osVersion)
                    InfoRow(key: "已运行", value: Fmt.uptime(since: h.bootDate))
                }

                group("处理器与内存", symbol: "cpu") {
                    InfoRow(key: "芯片", value: h.shortChip)
                    InfoRow(key: "架构", value: h.arch)
                    InfoRow(key: "核心", value: "\(h.physicalCores) 核 / \(h.logicalCores) 线程")
                    InfoRow(key: "内存", value: Fmt.bytes(h.memory))
                    if let t = m.sensors.cpuTemp { InfoRow(key: "CPU 温度", value: Fmt.temp(t)) }
                }

                if !h.gpu.isEmpty || !h.displays.isEmpty {
                    group("显卡与显示器", symbol: "display") {
                        if !h.gpu.isEmpty { InfoRow(key: "显卡", value: h.gpu) }
                        ForEach(h.displays, id: \.self) { InfoRow(key: "显示器", value: $0) }
                        if let t = m.sensors.gpuTemp { InfoRow(key: "GPU 温度", value: Fmt.temp(t)) }
                    }
                }

                if let b = m.battery {
                    group("电池", symbol: "battery.100percent") {
                        InfoRow(key: "电量", value: "\(b.percent)%" + (b.isCharging ? " · 充电中" : (b.onAC ? " · 已接电源" : "")))
                        if let mins = b.minutesRemaining { InfoRow(key: b.isCharging ? "充满还需" : "剩余时间", value: Fmt.minutes(mins)) }
                        if let hp = b.health { InfoRow(key: "最大容量", value: Fmt.percent(hp)) }
                        if let c = b.cycles { InfoRow(key: "循环次数", value: "\(c)") }
                        if let t = b.temperature { InfoRow(key: "电池温度", value: String(format: "%.1f°C", t)) }
                    }
                }

                if !m.sensors.fans.isEmpty {
                    group("散热", symbol: "fan") {
                        ForEach(m.sensors.fans) { fan in
                            InfoRow(key: fan.name, value: "\(Int(fan.rpm)) RPM（\(Int(fan.min)) – \(Int(fan.max))）")
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
