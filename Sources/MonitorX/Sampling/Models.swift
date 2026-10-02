import Foundation

struct CPUStats {
    var total = 0.0      // 0...1
    var user = 0.0
    var system = 0.0
    var perCore: [Double] = []
    var load: (Double, Double, Double) = (0, 0, 0)
}

struct MemStats {
    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var pressure = 1     // 1 normal, 2 warning, 4 critical

    var used: UInt64 { app + wired + compressed }
    var free: UInt64 { total > used + cached ? total - used - cached : 0 }
    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

struct NetStats {
    var downRate = 0.0   // bytes/s
    var upRate = 0.0
    var totalDown: UInt64 = 0   // this session
    var totalUp: UInt64 = 0
    var interface = "—"
    var ip = "—"
}

struct VolumeInfo: Identifiable {
    var id: String { path }
    var path: String
    var name: String
    var total: UInt64
    var free: UInt64
    var isInternal: Bool
    var used: UInt64 { total > free ? total - free : 0 }
    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

struct DiskStats {
    var volumes: [VolumeInfo] = []
    var readRate = 0.0
    var writeRate = 0.0
    /// Fraction used on the primary (boot) volume.
    var primaryUsed: Double { volumes.first?.usedFraction ?? 0 }
}

struct BatteryInfo {
    var percent = 0
    var isCharging = false
    var onAC = false
    var cycles: Int?
    var health: Double?      // 0...1
    var temperature: Double? // °C
    var minutesRemaining: Int?
}

enum SensorCategory: Int, CaseIterable {
    case cpu, gpu, battery, storage, memory, board, other

    var title: String {
        switch self {
        case .cpu: L("Processor")
        case .gpu: L("Graphics")
        case .battery: L("Battery")
        case .storage: L("Storage")
        case .memory: L("Memory")
        case .board: L("Mainboard & Ambient")
        case .other: L("Other")
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "display"
        case .battery: "battery.100percent"
        case .storage: "internaldrive"
        case .memory: "memorychip"
        case .board: "square.grid.3x3.topleft.filled"
        case .other: "thermometer.medium"
        }
    }
}

struct SensorReading: Identifiable {
    var id: String { key }
    var key: String
    var category: SensorCategory
    var value: Double   // °C
    /// Localized at display time so it follows the UI language.
    var name: String { SensorNames.name(for: key) }
}

struct FanReading: Identifiable {
    var id: Int
    var count: Int      // number of fans in the machine, used for naming
    var name: String {
        count == 2 ? (id == 0 ? L("Left Fan") : L("Right Fan")) : L("Fan %@", "\(id + 1)")
    }
    var rpm: Double
    var min: Double
    var max: Double
    /// 0...1 between the fan's minimum and maximum speed.
    var fraction: Double { max > min ? Swift.min(1, Swift.max(0, (rpm - min) / (max - min))) : 0 }
}

struct SensorInfo {
    var cpuTemp: Double?
    var gpuTemp: Double?
    var fans: [FanReading] = []
    var all: [SensorReading] = []
}

extension HardwareInfo {
    /// "Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz" -> "Intel Core i7-9750H · 2.6 GHz"
    var shortChip: String {
        var c = chip.replacingOccurrences(of: "(R)", with: "").replacingOccurrences(of: "(TM)", with: "")
            .replacingOccurrences(of: " CPU", with: "")
        if let r = c.range(of: " @ ") {
            let freq = c[r.upperBound...].replacingOccurrences(of: "GHz", with: " GHz")
            c = String(c[c.startIndex..<r.lowerBound]) + " · " + freq
        }
        return c.isEmpty ? arch : c
    }
}

struct HardwareInfo {
    var modelName = "Mac"
    var modelID = ""
    var chip = ""
    var physicalCores = 0
    var logicalCores = 0
    var memory: UInt64 = 0
    var serial = ""
    var osVersion = ""
    var gpus: [GPUInfo] = []
    var displays: [String] = []
    var bootDate = Date()
    var arch = ""
}

struct GPUInfo {
    var name: String
    var cores: String?
    var vram: String?

    var label: String {
        var s = name
        if let cores { s += " · " + L("%@ cores", cores) }
        if let vram { s += " · " + vram }
        return s
    }
}

extension HardwareInfo {
    var gpu: String { gpus.map(\.label).joined(separator: "\n") }
}

struct ProcessEntry: Identifiable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var groupKey: String
    var groupName: String
    var appPath: String?
    var cpu = 0.0           // % of one core
    var mem: UInt64 = 0     // bytes
    var netIn = 0.0         // bytes/s
    var netOut = 0.0
    var diskRead = 0.0
    var diskWrite = 0.0
}

enum ProcMetric {
    case cpu, memory, network, disk
}

struct ProcessGroup: Identifiable {
    var id: String
    var name: String
    var appPath: String?
    var members: [ProcessEntry]

    var cpu: Double { members.reduce(0) { $0 + $1.cpu } }
    var mem: UInt64 { members.reduce(0) { $0 + $1.mem } }
    var netIn: Double { members.reduce(0) { $0 + $1.netIn } }
    var netOut: Double { members.reduce(0) { $0 + $1.netOut } }
    var diskRead: Double { members.reduce(0) { $0 + $1.diskRead } }
    var diskWrite: Double { members.reduce(0) { $0 + $1.diskWrite } }

    func value(_ m: ProcMetric) -> Double {
        switch m {
        case .cpu: return cpu
        case .memory: return Double(mem)
        case .network: return netIn + netOut
        case .disk: return diskRead + diskWrite
        }
    }
}

extension ProcessEntry {
    func value(_ m: ProcMetric) -> Double {
        switch m {
        case .cpu: return cpu
        case .memory: return Double(mem)
        case .network: return netIn + netOut
        case .disk: return diskRead + diskWrite
        }
    }
}
