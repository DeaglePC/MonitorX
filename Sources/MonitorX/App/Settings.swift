import Foundation
import Observation
import ServiceManagement

enum MenuBarAppearance: String {
    case automatic, compact, detailed
}

@Observable
final class Settings {
    var showClaudeInMenuBar: Bool { didSet { save("showClaudeInMenuBar", showClaudeInMenuBar) } }
    var showCodexInMenuBar: Bool { didSet { save("showCodexInMenuBar", showCodexInMenuBar) } }
    var showCodexUsage: Bool { didSet { save("showCodexUsage", showCodexUsage) } }
    var menuBarAppearance: MenuBarAppearance {
        didSet { UserDefaults.standard.set(menuBarAppearance.rawValue, forKey: "menuBarAppearance") }
    }
    var showCPU: Bool { didSet { save("showCPU", showCPU) } }
    var showMemory: Bool { didSet { save("showMemory", showMemory) } }
    var showNetwork: Bool { didSet { save("showNetwork", showNetwork) } }
    var showDisk: Bool { didSet { save("showDisk", showDisk) } }
    var showTemperature: Bool { didSet { save("showTemperature", showTemperature) } }
    var showFan: Bool { didSet { save("showFan", showFan) } }
    var groupByApp: Bool { didSet { save("groupByApp", groupByApp) } }

    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["showClaudeInMenuBar": true])
        showClaudeInMenuBar = d.bool(forKey: "showClaudeInMenuBar")
        d.register(defaults: ["showCodexUsage": true, "showCodexInMenuBar": true])
        showCodexInMenuBar = d.bool(forKey: "showCodexInMenuBar")
        showCodexUsage = d.bool(forKey: "showCodexUsage")
        menuBarAppearance = MenuBarAppearance(rawValue: d.string(forKey: "menuBarAppearance") ?? "") ?? .automatic
        d.register(defaults: ["showCPU": true, "showMemory": true, "showNetwork": true, "showDisk": false,
                               "showTemperature": false, "showFan": false, "groupByApp": true])
        showCPU = d.bool(forKey: "showCPU")
        showMemory = d.bool(forKey: "showMemory")
        showNetwork = d.bool(forKey: "showNetwork")
        showDisk = d.bool(forKey: "showDisk")
        showTemperature = d.bool(forKey: "showTemperature")
        showFan = d.bool(forKey: "showFan")
        groupByApp = d.bool(forKey: "groupByApp")
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("MonitorX: launch-at-login failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func save(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
