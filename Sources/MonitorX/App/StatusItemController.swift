import AppKit

/// Owns the menu-bar item: renders live values into a compact template image and toggles the panel.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitor: SystemMonitor
    private let settings: Settings
    private let panel: PanelController

    init(monitor: SystemMonitor, settings: Settings, panel: PanelController) {
        self.monitor = monitor
        self.settings = settings
        self.panel = panel
        super.init()

        if let b = statusItem.button {
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.imagePosition = .imageOnly
        }
        monitor.onUpdate = { [weak self] in self?.refresh() }
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
        } else {
            panel.toggle(relativeTo: sender)
        }
    }

    @objc private func openPanel() {
        if let b = statusItem.button { panel.toggle(relativeTo: b) }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: rendering

    private struct Segment {
        var label: String?
        var lines: [String]
        var widthSample: String
    }

    func refresh() {
        var segs: [Segment] = []
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

        guard let button = statusItem.button else { return }
        if segs.isEmpty {
            let img = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "MonitorX")
            img?.isTemplate = true
            button.image = img
        } else {
            button.image = Self.render(segs)
        }
        button.toolTip = L("CPU %1$@ · Memory %2$@ · ↓%3$@ ↑%4$@",
                           Fmt.percent(monitor.cpu.total), Fmt.percent(monitor.mem.usedFraction),
                           Fmt.rate(monitor.net.downRate), Fmt.rate(monitor.net.upRate))
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
