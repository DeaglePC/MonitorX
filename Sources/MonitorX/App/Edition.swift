import Foundation

/// The App Store build (`-DAPPSTORE`) runs inside the App Sandbox, which forbids inspecting other processes,
/// spawning `ps` / `netstat` / `system_profiler` and talking to AppleSMC. Those features are compiled out.
enum Edition {
    #if APPSTORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif

    static var hasProcessDetail: Bool { !isAppStore }
    static var hasSensors: Bool { !isAppStore }
}
