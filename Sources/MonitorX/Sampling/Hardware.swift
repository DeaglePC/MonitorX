import Foundation
import AppKit
import IOKit
import IOKit.ps
import Metal

// MARK: - sysctl helpers

func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
    var buf = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &buf, &size, nil, 0)
    return String(cString: buf)
}

func sysctlInt(_ name: String) -> Int {
    var v: Int64 = 0
    var size = MemoryLayout<Int64>.size
    var v32: Int32 = 0
    var size32 = MemoryLayout<Int32>.size
    if sysctlbyname(name, &v, &size, nil, 0) == 0, size == 8 { return Int(v) }
    if sysctlbyname(name, &v32, &size32, nil, 0) == 0 { return Int(v32) }
    return 0
}

// MARK: - Static hardware info

enum HardwareLoader {
    /// Fast, sysctl-only part.
    static func quick() -> HardwareInfo {
        var h = HardwareInfo()
        h.modelID = sysctlString("hw.model")
        h.chip = sysctlString("machdep.cpu.brand_string")
        h.physicalCores = sysctlInt("hw.physicalcpu")
        h.logicalCores = sysctlInt("hw.logicalcpu")
        h.memory = UInt64(sysctlInt("hw.memsize"))
        let v = ProcessInfo.processInfo.operatingSystemVersion
        h.osVersion = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
            + " (\(sysctlString("kern.osversion")))"
        h.arch = sysctlInt("hw.optional.arm64") == 1 ? "Apple Silicon" : "Intel x86_64"
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 {
            h.bootDate = Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
        }
        return h
    }

    #if !APPSTORE
    /// Slower part (system_profiler, ~1 s) — model name, serial, GPU, displays.
    static func detailed(base: HardwareInfo) -> HardwareInfo {
        var h = base
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["-json", "SPHardwareDataType", "SPDisplaysDataType"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return h }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return h }

        if let hw = (root["SPHardwareDataType"] as? [[String: Any]])?.first {
            if let n = hw["machine_name"] as? String { h.modelName = n }
            if let s = hw["serial_number"] as? String { h.serial = s }
            if let chip = hw["chip_type"] as? String { h.chip = chip }
        }
        if let gpus = root["SPDisplaysDataType"] as? [[String: Any]] {
            for g in gpus {
                h.gpus.append(GPUInfo(name: (g["sppci_model"] as? String) ?? "GPU",
                                      cores: g["sppci_cores"] as? String,
                                      vram: (g["spdisplays_vram"] as? String) ?? (g["spdisplays_vram_shared"] as? String)))
                for d in (g["spdisplays_ndrvs"] as? [[String: Any]]) ?? [] {
                    let dn = (d["_name"] as? String) ?? "Display"
                    let res = (d["_spdisplays_resolution"] as? String) ?? (d["spdisplays_resolution"] as? String) ?? ""
                    h.displays.append(res.isEmpty ? dn : "\(dn) · \(res)")
                }
            }
        }
        return h
    }
    #else
    /// Sandbox-safe replacement: no `system_profiler`, so use IOKit registry / Metal / AppKit instead.
    static func detailed(base: HardwareInfo) -> HardwareInfo {
        var h = base
        h.modelName = marketingName(for: base.modelID)

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let serial = IORegistryEntryCreateCFProperty(service, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String { h.serial = serial }
        }

        h.gpus = MTLCopyAllDevices().map { GPUInfo(name: $0.name) }

        DispatchQueue.main.sync {
            h.displays = NSScreen.screens.map { screen in
                let scale = screen.backingScaleFactor
                let w = Int(screen.frame.width * scale), hgt = Int(screen.frame.height * scale)
                return "\(screen.localizedName) · \(w) x \(hgt)" + (scale > 1 ? " Retina" : "")
            }
        }
        return h
    }

    private static func marketingName(for model: String) -> String {
        let table = [("MacBookPro", "MacBook Pro"), ("MacBookAir", "MacBook Air"), ("MacBook", "MacBook"),
                     ("Macmini", "Mac mini"), ("MacPro", "Mac Pro"), ("MacStudio", "Mac Studio"),
                     ("iMacPro", "iMac Pro"), ("iMac", "iMac")]
        return table.first { model.hasPrefix($0.0) }?.1 ?? "Mac"
    }
    #endif
}

// MARK: - Battery

enum BatteryReader {
    static func read() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any],
              (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { return nil }

        var b = BatteryInfo()
        b.percent = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        b.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
        b.onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        if let t = desc[kIOPSTimeToEmptyKey] as? Int, t > 0, !b.onAC { b.minutesRemaining = t }
        if let t = desc[kIOPSTimeToFullChargeKey] as? Int, t > 0, b.isCharging { b.minutesRemaining = t }

        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if svc != 0 {
            defer { IOObjectRelease(svc) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any] {
                b.cycles = d["CycleCount"] as? Int
                if let t = d["Temperature"] as? Int { b.temperature = Double(t) / 100 }
                let design = d["DesignCapacity"] as? Int ?? 0
                // Apple Silicon reports MaxCapacity as a percentage and the raw mAh in AppleRawMaxCapacity.
                let rawMax = d["AppleRawMaxCapacity"] as? Int ?? d["MaxCapacity"] as? Int ?? 0
                if let m = d["MaxCapacity"] as? Int, m <= 100, d["AppleRawMaxCapacity"] == nil {
                    b.health = Double(m) / 100
                } else if design > 0, rawMax > 0 {
                    b.health = min(1, Double(rawMax) / Double(design))
                }
            }
        }
        return b
    }
}
