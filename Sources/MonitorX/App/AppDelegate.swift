import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SystemMonitor()
    private let settings = Settings()
    private var panel: PanelController!
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PanelController(monitor: monitor, settings: settings)
        statusItem = StatusItemController(monitor: monitor, settings: settings, panel: panel)
        monitor.start()

        // `MonitorX --show` opens the panel right away.
        if CommandLine.arguments.contains("--show"), let button = statusItem.button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.panel.show(relativeTo: button)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.shutdown()
    }
}
