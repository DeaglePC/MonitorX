import AppKit
import SwiftUI

@main
struct WindowLifecycleCheck {
    @MainActor static func main() {
        let defaults = UserDefaults.standard
        let keys = ["NSWindow Frame " + MainWindowController.frameAutosaveName, "menuBarClickBehavior", "showCodexUsage", "showClaudeUsage"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.finishLaunching()
        // A command-line harness does not enter NSApplication.run(), which delivers
        // the delegate launch callback in the real app. Exercise that callback explicitly.
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        guard let window = app.windows.first(where: { $0.title == "MonitorX" }) else {
            fatalError("Launch must create the main window")
        }
        precondition(window.isVisible, "Launch must show the main window without --show")
        precondition(app.activationPolicy() == .regular, "Visible window must have a Dock entry")
        precondition(window.styleMask.contains(.miniaturizable))
        precondition(window.styleMask.contains(.resizable))
        window.setContentSize(NSSize(width: 960, height: 700))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(abs((window.contentView?.bounds.width ?? 0) - 960) < 1, "Hosting content must expand with the window")
        let resized = window.frame
        window.performMiniaturize(nil)
        precondition(!window.isVisible, "Minimize must hide the window")
        precondition(!window.isMiniaturized, "Minimize must not leave a Dock thumbnail")
        precondition(app.activationPolicy() == .accessory)

        _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)
        precondition(window.isVisible, "Finder reopen must restore the window")
        precondition(abs(window.frame.width - resized.width) < 1, "Reopen must retain resized width")
        let expected = window.frame
        let restoreName = "MonitorX.RestoreCheck." + UUID().uuidString
        window.saveFrame(usingName: restoreName)
        defer { defaults.removeObject(forKey: "NSWindow Frame " + restoreName) }
        window.setContentSize(NSSize(width: 500, height: 600))
        // Use a separate saved snapshot: resizing correctly updates the live autosave name.
        precondition(window.setFrameUsingName(restoreName))
        precondition(abs(window.frame.width - expected.width) < 1, "Saved window frame must restore the resized dimensions")
        let fitted = MainWindowController.fitting(NSRect(x: 3000, y: -800, width: 1800, height: 1000),
                                                   inside: NSRect(x: 0, y: 0, width: 1200, height: 800))
        precondition(fitted == NSRect(x: 0, y: 0, width: 1200, height: 800), "Disconnected-monitor frames must fit on screen")
        window.performClose(nil)
        // Exercise the actual menu button with both click behaviors, including a visible main window.
        let settings = Settings(), monitor = SystemMonitor()
        settings.showCodexUsage = true
        settings.showClaudeUsage = true
        // Software-render the production responsive layout; native GPU-backed window caches omit text.
        monitor.claudeUsage.setupStatus = .signedIn
        let now = Date().timeIntervalSince1970
        monitor.codexUsage.buckets = [.init(limitId: "codex", limitName: nil,
            primary: .init(usedPercent: 20, windowDurationMins: 300, resetsAt: now + 3600), secondary: nil)]
        monitor.claudeUsage.snapshot = .init(updatedAt: now, windows: ["five_hour": .init(used_percentage: 25, resets_at: now + 3600)])
        for width in [CGFloat(420), 960] {
            let renderer = ImageRenderer(content: OverviewView(go: { _ in })
                .environment(monitor).environment(settings).environment(\.monitoringWidth, width)
                .environment(\.isSnapshot, true).environment(\.colorScheme, .dark)
                .frame(width: width).background(Color(white: 0.1)))
            renderer.scale = 1
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                fatalError("Responsive overview must render")
            }
            precondition(image.width == Int(width))
            try! data.write(to: URL(fileURLWithPath: "/tmp/MonitorX-overview-\(Int(width)).png"))
        }
        let panel = PanelController(monitor: monitor, settings: settings)
        let name = "MonitorX.WindowCheck." + UUID().uuidString
        defer { defaults.removeObject(forKey: "NSWindow Frame " + name) }
        let main = MainWindowController(monitor: monitor, settings: settings, panel: panel, autosaveName: name)
        let status = StatusItemController(monitor: monitor, settings: settings, panel: panel, mainWindow: main)
        settings.menuBarClickBehavior = .quickPanel
        main.show()
        status.button!.performClick(nil)
        precondition(panel.isVisible && main.isVisible, "Quick Panel preference must open the panel even when the main window is visible")
        settings.menuBarClickBehavior = .mainWindow
        precondition(Settings().menuBarClickBehavior == .mainWindow, "Click preference must persist")
        status.button!.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        precondition(main.isVisible && !panel.isVisible, "Main Window preference must show the window and dismiss the quick panel")
        app.windows.filter { $0.title == "MonitorX" && $0.isVisible }.forEach { $0.performClose(nil) }
        monitor.shutdown()
        precondition(!window.isVisible, "Close must hide the window")
        precondition(app.activationPolicy() == .accessory)
        precondition(!delegate.applicationShouldTerminateAfterLastWindowClosed(app))
        _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)
        precondition(window.isVisible, "Reopen after close must work")
        window.performClose(nil)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        print("Window lifecycle passed: launch, resize, frame restore, screen bounds, minimize/close/reopen, Dock policy and both menu click preferences")
    }
}
