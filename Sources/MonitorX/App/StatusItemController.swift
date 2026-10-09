import AppKit

/// Owns the menu-bar item: renders live values into a compact template image and toggles the panel.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitor: SystemMonitor
    private let settings: Settings
    private let panel: PanelController
    private let mainWindow: MainWindowController

    init(monitor: SystemMonitor, settings: Settings, panel: PanelController, mainWindow: MainWindowController) {
        self.monitor = monitor
        self.settings = settings
        self.panel = panel
        self.mainWindow = mainWindow
        super.init()

        if let b = statusItem.button {
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.imagePosition = .imageOnly
        }
        monitor.onUpdate = { [weak self] in self?.refresh() }
        monitor.codexUsage.onUpdate = { [weak self] in self?.refresh() }
        refresh()
    }

    var button: NSStatusBarButton? { statusItem.button }

    // MARK: click handling

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: L("Open MonitorX"), action: #selector(openPanel), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: L("Quit MonitorX"), action: #selector(quit), keyEquivalent: "q").target = self
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else if settings.menuBarClickBehavior == .mainWindow {
            mainWindow.show()
        } else {
            panel.toggle(relativeTo: sender)
        }
    }

    @objc private func openPanel() {
        mainWindow.show()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: rendering

    private struct Segment {
        var label: String?
        var lines: [String]
        var widthSample: String
    }

    func refresh() {
        if !Edition.isAppStore { monitor.claudeUsage.refresh() }
        let wantsClaude = !Edition.isAppStore && settings.showClaudeInMenuBar && monitor.claudeUsage.isConnected
        let wantsCodex = !Edition.isAppStore && settings.showCodexInMenuBar
        monitor.codexUsage.setEnabled(!Edition.isAppStore && (settings.showCodexUsage || wantsCodex))
        var segs: [Segment] = []
        let codexSegment = Segment(label: "CODEX", lines: [monitor.codexUsage.menuBarRemaining.map {
            Fmt.percent($0 / 100) + (monitor.codexUsage.errorKey == nil ? "" : "*")
        } ?? "–"], widthSample: "100%*")
        if wantsCodex { segs.append(codexSegment) }
        let claudeSegment = Segment(label: "CLAUDE", lines: [monitor.claudeUsage.menuBarRemaining.map {
            Fmt.percent($0 / 100) + (monitor.claudeUsage.isStale ? "*" : "")
        } ?? "–"], widthSample: "100%*")
        if wantsClaude { segs.append(claudeSegment) }
        if settings.showCPU {
            segs.append(Segment(label: "CPU", lines: [Fmt.percent(monitor.cpu.total)], widthSample: "100%"))
        }
        if settings.showMemory {
            segs.append(Segment(label: "MEM", lines: [Fmt.percent(monitor.mem.usedFraction)], widthSample: "100%"))
        }
        if settings.showNetwork {
            segs.append(Segment(label: nil,
                                lines: ["↓ " + Fmt.rateCompact(monitor.net.downRate), "↑ " + Fmt.rateCompact(monitor.net.upRate)],
                                widthSample: "↓ 999M"))
        }
        if settings.showDisk {
            segs.append(Segment(label: nil,
                                lines: ["R " + Fmt.rateCompact(monitor.disk.readRate), "W " + Fmt.rateCompact(monitor.disk.writeRate)],
                                widthSample: "R 999M"))
        }
        let wantsTemp = Edition.hasSensors && settings.showTemperature
        let wantsFan = Edition.hasSensors && settings.showFan
        monitor.setMenuBarSensors(wantsTemp || wantsFan)
        if wantsTemp {
            segs.append(Segment(label: "TEMP", lines: [monitor.sensors.cpuTemp.map { "\(Int($0.rounded()))°" } ?? "–"],
                                widthSample: "100°"))
        }
        if wantsFan, !monitor.sensors.fans.isEmpty || monitor.sensors.cpuTemp == nil {
            segs.append(Segment(label: "FAN", lines: [monitor.sensors.fans.map(\.rpm).max().map { "\(Int($0))" } ?? "–"],
                                widthSample: "8888"))
        }

        guard let button = statusItem.button else { return }
        // macOS owns status-item placement. Use a square item on camera-housing
        // displays by default to leave space in the narrow menu-bar area.
        let screen = button.window?.screen ?? NSScreen.main
        let compact = settings.menuBarAppearance == .compact ||
            (settings.menuBarAppearance == .automatic && (screen?.safeAreaInsets.top ?? 0) > 0)
        if compact && (wantsCodex || wantsClaude) && settings.menuBarAppearance != .compact {
            // Keep the requested quota visible while omitting wider system metrics on a notched screen.
            statusItem.length = NSStatusItem.variableLength
            button.image = Self.render((wantsCodex ? [codexSegment] : []) + (wantsClaude ? [claudeSegment] : []))
        } else if segs.isEmpty || compact {
            statusItem.length = NSStatusItem.squareLength
            let img = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "MonitorX")
            img?.isTemplate = true
            button.image = img
        } else {
            statusItem.length = NSStatusItem.variableLength
            button.image = Self.render(segs)
        }
        button.toolTip = L("CPU %1$@ · Memory %2$@ · ↓%3$@ ↑%4$@",
                           Fmt.percent(monitor.cpu.total), Fmt.percent(monitor.mem.usedFraction),
                           Fmt.rate(monitor.net.downRate), Fmt.rate(monitor.net.upRate))
        if wantsCodex {
            var lines = [L("Codex Usage")]
            for bucket in monitor.codexUsage.buckets {
                lines.append(bucket.title)
                for window in bucket.windows {
                    lines.append(window.duration + " · " + L("Remaining: %@", window.remaining.map { Fmt.percent($0 / 100) } ?? "—"))
                    if let reset = window.resetsAt {
                        lines.append(L("Resets: %@", Date(timeIntervalSince1970: reset).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale))))
                    }
                }
            }
            if let error = monitor.codexUsage.errorKey {
                lines.append(error == "Codex CLI not found" ? L("Codex CLI not found") : L("Couldn't read Codex usage. Sign in to Codex with ChatGPT."))
            }
            if let date = monitor.codexUsage.updatedAt {
                lines.append(L("Updated: %@", date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale))))
            }
            button.toolTip = (button.toolTip ?? "") + "\n\n" + lines.joined(separator: "\n")
        }
        if wantsClaude {
            var lines = [L("Claude Usage")]
            for window in monitor.claudeUsage.windows {
                lines.append(window.duration + " · " + L("Remaining: %@", window.remaining.map { Fmt.percent($0 / 100) } ?? "—"))
                if let reset = window.resetsAt {
                    lines.append(L("Resets: %@", Date(timeIntervalSince1970: reset).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale))))
                }
            }
            if let snapshot = monitor.claudeUsage.snapshot {
                if monitor.claudeUsage.isStale { lines.append(L("Last reading (may be outdated)")) }
                lines.append(L("Updated: %@", Date(timeIntervalSince1970: snapshot.updatedAt).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale))))
            } else { lines.append(L("Start a Claude Code conversation to update usage.")) }
            button.toolTip = (button.toolTip ?? "") + "\n\n" + lines.joined(separator: "\n")
        }
    }

    private static func render(_ segs: [Segment]) -> NSImage {
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let smallFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        let labelFont = NSFont.systemFont(ofSize: 7.5, weight: .bold)
        let height: CGFloat = 22
        let gap: CGFloat = 9

        func width(of s: String, _ f: NSFont) -> CGFloat {
            ceil((s as NSString).size(withAttributes: [.font: f]).width)
        }
        let widths = segs.map { seg -> CGFloat in
            let f = seg.lines.count > 1 ? smallFont : valueFont
            return max(width(of: seg.widthSample, f), seg.label.map { width(of: $0, labelFont) } ?? 0)
        }
        let total = widths.reduce(0, +) + gap * CGFloat(segs.count - 1)

        let image = NSImage(size: NSSize(width: total, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (i, seg) in segs.enumerated() {
                let w = widths[i]
                func draw(_ s: String, font: NSFont, y: CGFloat, alignRight: Bool = false, alpha: CGFloat = 1) {
                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black.withAlphaComponent(alpha)]
                    let sw = (s as NSString).size(withAttributes: attrs).width
                    (s as NSString).draw(at: NSPoint(x: alignRight ? x + w - sw : x + (w - sw) / 2, y: y), withAttributes: attrs)
                }
                if let label = seg.label {
                    draw(label, font: labelFont, y: 12.5, alpha: 0.7)
                    draw(seg.lines[0], font: valueFont, y: 0.5)
                } else {
                    draw(seg.lines[0], font: smallFont, y: 10.5, alignRight: true)
                    draw(seg.lines[1], font: smallFont, y: 0, alignRight: true)
                }
                x += w + gap
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
