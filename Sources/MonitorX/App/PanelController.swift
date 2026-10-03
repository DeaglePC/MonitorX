import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// A borderless panel whose background is a real macOS 26 Liquid Glass surface (`NSGlassEffectView`).
final class PanelController: NSObject {
    static let size = NSSize(width: 420, height: 660)

    private let panel: FloatingPanel
    private let monitor: SystemMonitor
    private let state = PanelState()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// The user dragged the panel away from the menu bar: it then stays open when clicking elsewhere
    /// (close it with Esc or the menu-bar item) and is re-anchored under the menu bar the next time it opens.
    private var detached = false
    private var positioning = false

    init(monitor: SystemMonitor, settings: Settings) {
        self.monitor = monitor
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        super.init()

        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let root = RootView()
            .environment(monitor)
            .environment(settings)
            .environment(state)
        let host = NSHostingView(rootView: root)
        host.safeAreaRegions = []

        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: Self.size))
        glass.cornerRadius = Self.cornerRadius
        glass.contentView = host
        glass.autoresizingMask = [.width, .height]

        // Clip the whole window content to the rounded shape: anything drawn into the square corners would
        // otherwise make the window server's shadow / edge follow the rectangle instead of the rounded glass.
        let container = NSView(frame: NSRect(origin: .zero, size: Self.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = Self.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.addSubview(glass)
        panel.contentView = container

        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self, !self.positioning, self.panel.isVisible, !self.detached else { return }
            self.detached = true
            self.panel.level = .floating   // an ordinary floating window now, below menus and pop-ups
        }
    }

    private static let cornerRadius: CGFloat = 30

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo button: NSStatusBarButton) {
        isVisible ? hide() : show(relativeTo: button)
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let buttonFrame = window.frame
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        var x = buttonFrame.midX - Self.size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - Self.size.width - 8)
        let y = max(visible.minY + 8, buttonFrame.minY - Self.size.height - 6)
        positioning = true
        panel.setFrame(NSRect(x: x, y: y, width: Self.size.width, height: Self.size.height), display: true)
        positioning = false
        detached = false
        panel.level = .popUpMenu

        state.isOpen = true
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        // The shadow is computed from the window's pixels; recompute it once the rounded content has drawn.
        DispatchQueue.main.async { [panel] in panel.invalidateShadow() }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }
        monitor.setDetailActive(true)

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, !self.state.isPresentingDialog, !self.detached else { return }
            self.hide()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53, self?.state.isPresentingDialog == false { self?.hide(); return nil }   // esc
            return event
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
            self.state.isOpen = false
        })
        monitor.setDetailActive(false)
    }
}
