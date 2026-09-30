import Foundation
import Observation
import ServiceManagement

@Observable
final class Settings {
    var showCPU: Bool { didSet { save("showCPU", showCPU) } }
    var showMemory: Bool { didSet { save("showMemory", showMemory) } }
    var showNetwork: Bool { didSet { save("showNetwork", showNetwork) } }
    var showDisk: Bool { didSet { save("showDisk", showDisk) } }
    var groupByApp: Bool { didSet { save("groupByApp", groupByApp) } }

    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["showCPU": true, "showMemory": true, "showNetwork": true, "showDisk": false, "groupByApp": true])
        showCPU = d.bool(forKey: "showCPU")
        showMemory = d.bool(forKey: "showMemory")
        showNetwork = d.bool(forKey: "showNetwork")
        showDisk = d.bool(forKey: "showDisk")
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
