import AppKit

/// A localized, plain-text snapshot of the current readings, following image sharing's serial-number policy.
@MainActor
enum TextSnapshot {
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    static func report(tabs: [Tab], monitor m: SystemMonitor, settings: Settings, date: Date) -> String {
        let stamp = date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(Localizer.shared.locale))
        let sections = tabs.filter { Tab.available.contains($0) }.map {
            "[\($0.title)]\n" + page($0, m, settings).joined(separator: "\n")
        }
        return (["MonitorX · \(stamp)", m.hardware.modelName] + sections).joined(separator: "\n\n") + "\n"
    }

    private static func page(_ tab: Tab, _ m: SystemMonitor, _ settings: Settings) -> [String] {
        func row(_ name: String, _ value: String) -> String { "\(name): \(value)" }
        let h = m.hardware
        var lines: [String] = []
        switch tab {
        case .overview:
            if !Edition.isAppStore, let snapshot = m.claudeUsage.snapshot {
                lines.append(L("Claude Usage"))
                if m.claudeUsage.isStale { lines.append(L("Last reading (may be outdated)")) }
                for window in snapshot.quotaWindows {
                    lines.append(window.duration + " · " + L("Remaining: %@", window.remaining.map { Fmt.percent($0 / 100) } ?? "—"))
                    if let reset = window.resetsAt {
                        lines.append(L("Resets: %@", Date(timeIntervalSince1970: reset).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale))))
                    }
                }
                lines.append(L("Updated: %@", Date(timeIntervalSince1970: snapshot.updatedAt).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale))))
            }
            lines += [row(L("Chip"), h.shortChip), row(L("Uptime"), Fmt.uptime(since: h.bootDate)),
                     row(L("CPU"), Fmt.percent(m.cpu.total)),
                     row(L("Memory"), "\(Fmt.bytes(m.mem.used)) / \(Fmt.bytes(m.mem.total)) (\(Fmt.percent(m.mem.usedFraction)))"),
                     row(L("Download"), Fmt.rate(m.net.downRate)), row(L("Upload"), Fmt.rate(m.net.upRate)),
                     L("Read %@", Fmt.rate(m.disk.readRate)), L("Write %@", Fmt.rate(m.disk.writeRate))]
            if let v = m.disk.volumes.first { lines.append(row(L("Disk"), "\(v.name) · \(Fmt.percent(v.usedFraction))")) }
            if let t = m.sensors.cpuTemp { lines.append(row(L("CPU Temperature"), Fmt.temp(t))) }
            lines += battery(m.battery)
            if !Edition.isAppStore && settings.showCodexUsage {
                lines.append(L("Codex Usage"))
                for bucket in m.codexUsage.buckets {
                    lines.append(bucket.title)
                    for window in bucket.windows {
                        lines.append("  \(window.duration) · " + L("Remaining: %@", window.remaining.map { Fmt.percent($0 / 100) } ?? "—"))
                        lines.append("  " + L("Resets: %@", window.resetsAt.map {
                            Date(timeIntervalSince1970: $0).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale))
                        } ?? "—"))
                    }
                }
                if let error = m.codexUsage.errorKey {
                    lines.append(error == "Codex CLI not found" ? L("Codex CLI not found") : L("Couldn't read Codex usage. Sign in to Codex with ChatGPT."))
                } else if m.codexUsage.buckets.flatMap(\.windows).isEmpty { lines.append(L("No quota data available")) }
                if let updated = m.codexUsage.updatedAt {
                    lines.append(L("Updated: %@", updated.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale))))
                }
            }
        case .cpu:
            lines = [row(L("Chip"), h.shortChip), L("%1$@ cores · %2$@ threads", "\(h.physicalCores)", "\(h.logicalCores)"),
                     row(L("Total"), Fmt.percent(m.cpu.total)), row(L("User"), Fmt.percent(m.cpu.user, digits: 1)),
                     row(L("System"), Fmt.percent(m.cpu.system, digits: 1)),
                     row(L("Idle"), Fmt.percent(max(0, 1 - m.cpu.total), digits: 1)),
                     row(L("Load 1/5/15m"), String(format: "%.2f / %.2f / %.2f", m.cpu.load.0, m.cpu.load.1, m.cpu.load.2))]
            if let t = m.sensors.cpuTemp { lines.append(row(L("Temperature"), Fmt.temp(t))) }
            lines.append(L("Per Core"))
            lines += m.cpu.perCore.enumerated().map { "  \($0.offset + 1): \(Fmt.percent($0.element, digits: 1))" }
            lines += processes(.cpu, m, settings)
        case .memory:
            let mem = m.mem
            lines = [row(L("Total"), Fmt.bytes(mem.total)), row(L("Used"), Fmt.bytes(mem.used)),
                     row(L("Memory"), Fmt.percent(mem.usedFraction)), row(L("App Memory"), Fmt.bytes(mem.app)),
                     row(L("Wired Memory"), Fmt.bytes(mem.wired)), row(L("Compressed"), Fmt.bytes(mem.compressed)),
                     row(L("Cached Files"), Fmt.bytes(mem.cached)), row(L("Free"), Fmt.bytes(mem.free)),
                     L("Memory pressure · %@", mem.pressure == 4 ? L("Critical") : (mem.pressure == 2 ? L("Warning") : L("Normal"))),
                     L("Swap %1$@ / %2$@", Fmt.bytes(mem.swapUsed), Fmt.bytes(mem.swapTotal))]
            lines += processes(.memory, m, settings)
        case .network:
            lines = [m.net.interface == "—" ? L("Not connected") : "\(m.net.interface) · \(m.net.ip)",
                     row(L("Download"), Fmt.rate(m.net.downRate)), L("Total this session: %@", Fmt.bytes(m.net.totalDown)),
                     row(L("Upload"), Fmt.rate(m.net.upRate)), L("Total this session: %@", Fmt.bytes(m.net.totalUp))]
            lines += processes(.network, m, settings)
        case .disk:
            lines = [L("Read %@", Fmt.rate(m.disk.readRate)), L("Write %@", Fmt.rate(m.disk.writeRate)),
                     L("%@ local volumes", "\(m.disk.volumes.count)")]
            for v in m.disk.volumes {
                lines += ["\(v.name) (\(v.path)) · \(Fmt.percent(v.usedFraction))",
                          "  " + L("Used: %@", Fmt.bytes(v.used)), "  " + L("Available: %@", Fmt.bytes(v.free)),
                          "  " + L("Total: %@", Fmt.bytes(v.total))]
            }
            lines += processes(.disk, m, settings)
        case .sensors:
            lines = [L("%1$@ temperature sensors · %2$@ fans", "\(m.sensors.all.count)", "\(m.sensors.fans.count)")]
            if let hottest = m.sensors.all.max(by: { $0.value < $1.value }) {
                lines += [row(L("Hottest"), "\(hottest.name) · \(Fmt.temp(hottest.value))"),
                          row(L("Average"), Fmt.temp(m.sensors.all.map(\.value).reduce(0, +) / Double(m.sensors.all.count)))]
            } else { lines.append(L("Reading sensors…")) }
            for category in SensorCategory.allCases {
                let readings = m.sensors.all.filter { $0.category == category }.sorted { $0.value > $1.value }
                if !readings.isEmpty { lines.append(category.title) }
                lines += readings.map { "  \($0.name): \(Fmt.temp($0.value))" }
            }
            lines += fans(m.sensors.fans)
        case .hardware:
            lines = [row(L("Model"), h.modelName), row(L("Model Identifier"), h.modelID),
                     row(L("Operating System"), h.osVersion), row(L("Uptime"), Fmt.uptime(since: h.bootDate)),
                     row(L("Chip"), h.shortChip), row(L("Architecture"), h.arch),
                     row(L("Cores"), L("%1$@ cores / %2$@ threads", "\(h.physicalCores)", "\(h.logicalCores)")),
                     row(L("Memory"), Fmt.bytes(h.memory))]
            if !h.gpu.isEmpty { lines.append(row(L("Graphics"), h.gpu)) }
            lines += h.displays.map { row(L("Display"), $0) }
            if let t = m.sensors.cpuTemp { lines.append(row(L("CPU Temperature"), Fmt.temp(t))) }
            if let t = m.sensors.gpuTemp { lines.append(row(L("GPU Temperature"), Fmt.temp(t))) }
            lines += battery(m.battery) + fans(m.sensors.fans)
        }
        return lines
    }

    private static func battery(_ b: BatteryInfo?) -> [String] {
        guard let b else { return [] }
        var lines = ["\(L("Battery")): \(b.percent)% · \(b.isCharging ? L("Charging") : (b.onAC ? L("Power Adapter") : L("On Battery")))"]
        if let v = b.minutesRemaining { lines.append("\(b.isCharging ? L("Time to Full") : L("Time Remaining")): \(Fmt.minutes(v))") }
        if let v = b.health { lines.append("\(L("Maximum Capacity")): \(Fmt.percent(v))") }
        if let v = b.cycles { lines.append("\(L("Cycle Count")): \(v)") }
        if let v = b.temperature { lines.append("\(L("Battery Temperature")): \(String(format: "%.1f°C", v))") }
        return lines
    }

    private static func fans(_ fans: [FanReading]) -> [String] {
        fans.map { "\($0.name): " + L("%1$@ RPM (%2$@ – %3$@)", "\(Int($0.rpm))", "\(Int($0.min))", "\(Int($0.max))") }
    }

    private static func processes(_ metric: ProcMetric, _ m: SystemMonitor, _ settings: Settings) -> [String] {
        guard Edition.hasProcessDetail else { return [] }
        let title: String
        switch metric {
        case .cpu: title = L("Top CPU Usage")
        case .memory: title = L("Top Memory Usage")
        case .network: title = L("Top Network Traffic")
        case .disk: title = L("Top Disk Activity")
        }
        let header = "\(title) · \(settings.groupByApp ? L("Apps") : L("Processes"))"
        guard m.processesReady else { return [header, L("Collecting process data…")] }
        let groups = m.top(metric, grouped: settings.groupByApp, limit: 8)
        guard !groups.isEmpty else { return [header, metric == .network ? L("No processes using the network") : L("No activity")] }
        return [header] + groups.map { g in
            let value: String
            switch metric {
            case .cpu: value = Fmt.cpuPercent(g.cpu)
            case .memory: value = Fmt.bytes(g.mem)
            case .network: value = "↓ \(Fmt.rate(g.netIn)) · ↑ \(Fmt.rate(g.netOut))"
            case .disk: value = L("R %@", Fmt.rate(g.diskRead)) + " · " + L("W %@", Fmt.rate(g.diskWrite))
            }
            return "  \(g.name): \(value)"
        }
    }
}
