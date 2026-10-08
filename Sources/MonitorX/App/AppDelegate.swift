import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SystemMonitor()
    private let settings = Settings()
    private var panel: PanelController!
    private var statusItem: StatusItemController!
    private var mainWindow: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PanelController(monitor: monitor, settings: settings)
        mainWindow = MainWindowController(monitor: monitor, settings: settings, panel: panel)
        statusItem = StatusItemController(monitor: monitor, settings: settings, panel: panel, mainWindow: mainWindow)
        monitor.start()

        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "MonitorX")
        applicationMenu.addItem(withTitle: L("Open MonitorX"), action: #selector(openWindow), keyEquivalent: "0").target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: L("Quit MonitorX"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        NSApp.mainMenu = menu

        DispatchQueue.main.async { [weak self] in
            self?.mainWindow.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow?.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func openWindow() { mainWindow.show() }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.shutdown()
    }
}
