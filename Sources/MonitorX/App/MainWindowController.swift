import AppKit
import SwiftUI

/// The yellow window button sends the app to the menu bar instead of the Dock.
private final class MonitorWindow: NSWindow {
    var minimizeToMenuBar: (() -> Void)?
    override func miniaturize(_ sender: Any?) { minimizeToMenuBar?() }
}

final class MainWindowController: NSObject, NSWindowDelegate {
    static let frameAutosaveName = "MonitorX.MainWindow"
    private let window: MonitorWindow
    private let monitor: SystemMonitor
    private let panel: PanelController
    private let state = PanelState()
    private let autosaveName: String

    init(monitor: SystemMonitor, settings: Settings, panel: PanelController, autosaveName: String = MainWindowController.frameAutosaveName) {
        self.monitor = monitor
        self.panel = panel
        self.autosaveName = autosaveName
        window = MonitorWindow(contentRect: NSRect(origin: .zero, size: PanelController.size),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
        super.init()
        window.title = "MonitorX"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 420, height: 480)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentView = NSHostingView(rootView: RootView()
            .environment(monitor).environment(settings).environment(state))
        window.center()
        window.setFrameAutosaveName(autosaveName)
        window.setFrameUsingName(autosaveName)
        window.minimizeToMenuBar = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        panel.hide()
        state.isOpen = true
        NSApp.setActivationPolicy(.regular)
        // Re-clamp after display changes, including disconnecting an external display.
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            window.setFrame(Self.fitting(window.frame, inside: visible), display: true)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor.setDetailActive(true, source: .mainWindow)
    }

    /// Keep restored windows reachable after a monitor is unplugged or its resolution changes.
    static func fitting(_ frame: NSRect, inside visible: NSRect) -> NSRect {
        let size = NSSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
        return NSRect(x: max(visible.minX, min(frame.minX, visible.maxX - size.width)),
                      y: max(visible.minY, min(frame.minY, visible.maxY - size.height)),
                      width: size.width, height: size.height)
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        let frame = NSRect(x: window.frame.minX, y: window.frame.maxY - 760, width: 960, height: 760)
        return Self.fitting(frame, inside: (window.screen ?? NSScreen.main)?.visibleFrame ?? newFrame)
    }

    private func hide() {
        window.saveFrame(usingName: autosaveName)
        window.orderOut(nil)
        state.isOpen = false
        monitor.setDetailActive(false, source: .mainWindow)
        NSApp.setActivationPolicy(.accessory)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
