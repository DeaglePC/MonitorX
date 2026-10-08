import AppKit
import SwiftUI

/// The yellow window button sends the app to the menu bar instead of the Dock.
private final class MonitorWindow: NSWindow {
    var minimizeToMenuBar: (() -> Void)?
    override func miniaturize(_ sender: Any?) { minimizeToMenuBar?() }
}

final class MainWindowController: NSObject, NSWindowDelegate {
    private let window: MonitorWindow
    private let monitor: SystemMonitor
    private let panel: PanelController
    private let state = PanelState()

    init(monitor: SystemMonitor, settings: Settings, panel: PanelController) {
        self.monitor = monitor
        self.panel = panel
        window = MonitorWindow(contentRect: NSRect(origin: .zero, size: PanelController.size),
                               styleMask: [.titled, .closable, .miniaturizable],
                               backing: .buffered, defer: false)
        super.init()
        window.title = "MonitorX"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: RootView()
            .environment(monitor).environment(settings).environment(state))
        window.center()
        window.minimizeToMenuBar = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        panel.hide()
        state.isOpen = true
        NSApp.setActivationPolicy(.regular)
        // Re-clamp after display changes, including disconnecting an external display.
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            var frame = window.frame
            frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
            window.setFrame(frame, display: true)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor.setDetailActive(true)
    }

    private func hide() {
        window.orderOut(nil)
        state.isOpen = false
        monitor.setDetailActive(false)
        NSApp.setActivationPolicy(.accessory)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
