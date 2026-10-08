import AppKit

@main
struct TextSharingCheck {
    @MainActor static func main() {
        let previous = Localizer.shared.language
        defer { Localizer.shared.language = previous }
        Localizer.shared.language = .en
        let monitor = SystemMonitor()
        let settings = Settings()
        monitor.hardware.modelName = "Fixture Mac"
        monitor.hardware.serial = "SERIAL-MUST-NOT-BE-SHARED"
        monitor.cpu.total = 0.42
        monitor.cpu.perCore = [0.25, 0.59]
        monitor.mem.total = 8 * 1024 * 1024 * 1024
        monitor.mem.app = 2 * 1024 * 1024 * 1024
        monitor.net.downRate = 2048
        monitor.net.upRate = 1024
        monitor.net.interface = "en0"
        monitor.net.ip = "192.0.2.1"
        monitor.disk.volumes = [VolumeInfo(path: "/", name: "Test Disk", total: 1000, free: 400, isInternal: true)]
        monitor.sensors.all = [SensorReading(key: "TC0P", category: .cpu, value: 48)]
        monitor.sensors.fans = [FanReading(id: 0, count: 1, rpm: 2000, min: 1200, max: 5000)]
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let cpu = TextSnapshot.report(tabs: [.cpu], monitor: monitor, settings: settings, date: date)
        precondition(cpu.contains("[CPU]") && cpu.contains("42%") && cpu.contains("25.0%"))
        precondition(!cpu.contains("[Memory]"), "Current page export must stay scoped")
        monitor.cpu.total = 0.99
        precondition(cpu.contains("42%") && !cpu.contains("99%"), "Export must retain captured readings")

        let all = TextSnapshot.report(tabs: Tab.available, monitor: monitor, settings: settings, date: date)
        for tab in Tab.available { precondition(all.contains("[\(tab.title)]")) }
        precondition(all.contains("en0 · 192.0.2.1") && all.contains("2.00 KB/s"))
        precondition(all.contains("Test Disk") && all.contains("Available: 400 B"))
        precondition(!all.contains(monitor.hardware.serial), "Sharing must omit the serial number")
        if Edition.hasSensors { precondition(all.contains("48°C") && all.contains("2000 RPM")) }
        precondition(all.contains("Collecting process data…") == Edition.hasProcessDetail)

        if Edition.hasProcessDetail {
            let grouped = settings.groupByApp
            defer { settings.groupByApp = grouped }
            monitor.processesReady = true
            let entry = ProcessEntry(pid: 123, name: "Fixture Process", groupKey: "fixture", groupName: "Fixture App",
                                     cpu: 250, mem: 1024, netIn: 2048, diskRead: 4096)
            monitor.groups = [ProcessGroup(id: "fixture", name: "Fixture App", members: [entry])]
            settings.groupByApp = true
            let apps = TextSnapshot.report(tabs: [.cpu], monitor: monitor, settings: settings, date: date)
            precondition(apps.contains("Fixture App: 250%") && !apps.contains("Fixture Process"))
            settings.groupByApp = false
            let processes = TextSnapshot.report(tabs: [.cpu], monitor: monitor, settings: settings, date: date)
            precondition(processes.contains("Fixture Process: 250%") && !processes.contains("Fixture App"))
        }

        Localizer.shared.language = .zhHans
        let chinese = TextSnapshot.report(tabs: [.hardware], monitor: monitor, settings: settings, date: date)
        precondition(chinese.contains("[硬件]") && chinese.contains("系统:"))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        precondition(TextSnapshot.copy(chinese, to: board))
        precondition(board.string(forType: .string) == chinese)
        print("Text sharing passed: page scope, all pages, metrics, captured readings, localization, serial omission and clipboard")
    }
}
