import AppKit

@main
struct WindowLifecycleCheck {
    static func main() {
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
        window.performMiniaturize(nil)
        precondition(!window.isVisible, "Minimize must hide the window")
        precondition(!window.isMiniaturized, "Minimize must not leave a Dock thumbnail")
        precondition(app.activationPolicy() == .accessory)

        _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)
        precondition(window.isVisible, "Finder reopen must restore the window")
        window.performClose(nil)
        precondition(!window.isVisible, "Close must hide the window")
        precondition(app.activationPolicy() == .accessory)
        precondition(!delegate.applicationShouldTerminateAfterLastWindowClosed(app))
        _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)
        precondition(window.isVisible, "Reopen after close must work")
        window.performClose(nil)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        print("Window lifecycle passed: launch, minimize to menu bar, close, Finder reopen and Dock policy")
    }
}
