import Foundation

/// Human-readable names for well-known SMC temperature keys.
/// Names are English localization keys (optionally a `%@` format filled with `arg`), resolved at display time.
enum SensorNames {
    private struct Entry {
        let name: String
        var arg: String? = nil
        let category: SensorCategory
    }

    private static let known: [String: Entry] = [
        "TC0D": Entry(name: "CPU Diode", category: .cpu),
        "TC0E": Entry(name: "CPU Diode (Virtual)", category: .cpu),
        "TC0F": Entry(name: "CPU Diode (Filtered)", category: .cpu),
        "TC0H": Entry(name: "CPU Heatsink", category: .cpu),
        "TC0P": Entry(name: "CPU Proximity", category: .cpu),
        "TCAD": Entry(name: "CPU Package", category: .cpu),
        "TCXC": Entry(name: "CPU %@", arg: "PECI", category: .cpu),
        "TCMX": Entry(name: "CPU Hottest Core", category: .cpu),
        "TCSA": Entry(name: "CPU System Agent", category: .cpu),
        "TCGC": Entry(name: "Integrated GPU", category: .gpu),
        "TG0D": Entry(name: "GPU Diode", category: .gpu),
        "TG0H": Entry(name: "GPU Heatsink", category: .gpu),
        "TG0P": Entry(name: "GPU Proximity", category: .gpu),
        "TG1P": Entry(name: "GPU Proximity %@", arg: "2", category: .gpu),
        "TGDD": Entry(name: "Discrete GPU", category: .gpu),
        "TGDE": Entry(name: "Discrete GPU Core", category: .gpu),
        "TGDF": Entry(name: "Discrete GPU Memory", category: .gpu),
        "TGVF": Entry(name: "GPU Voltage Regulator %@", arg: "F", category: .gpu),
        "TGVP": Entry(name: "GPU Voltage Regulator %@", arg: "P", category: .gpu),
        "TB0T": Entry(name: "Battery %@", arg: "1", category: .battery),
        "TB1T": Entry(name: "Battery %@", arg: "2", category: .battery),
        "TB2T": Entry(name: "Battery %@", arg: "3", category: .battery),
        "TB3T": Entry(name: "Battery %@", arg: "4", category: .battery),
        "TH0F": Entry(name: "SSD Controller %@", arg: "F", category: .storage),
        "TH0X": Entry(name: "SSD %@", arg: "X", category: .storage),
        "TH0a": Entry(name: "SSD %@", arg: "A", category: .storage),
        "TH0b": Entry(name: "SSD %@", arg: "B", category: .storage),
        "TH1a": Entry(name: "SSD %@", arg: "2 A", category: .storage),
        "TH1b": Entry(name: "SSD %@", arg: "2 B", category: .storage),
        "TH0P": Entry(name: "Drive Proximity", category: .storage),
        "TH0A": Entry(name: "SSD %@", arg: "A", category: .storage),
        "TM0P": Entry(name: "Memory Proximity", category: .memory),
        "TM0S": Entry(name: "Memory Slot %@", arg: "1", category: .memory),
        "TM1S": Entry(name: "Memory Slot %@", arg: "2", category: .memory),
        "Tm0P": Entry(name: "Mainboard Proximity", category: .board),
        "TPCD": Entry(name: "Platform Controller Hub (PCH)", category: .board),
        "TN0P": Entry(name: "Northbridge Proximity", category: .board),
        "TW0P": Entry(name: "AirPort Proximity", category: .board),
        "TA0P": Entry(name: "Ambient", category: .board),
        "TA0V": Entry(name: "Ambient (Intake)", category: .board),
        "TaLC": Entry(name: "Left Air Intake", category: .board),
        "TaRC": Entry(name: "Right Air Intake", category: .board),
        "Ts0P": Entry(name: "Palm Rest Left", category: .board),
        "Ts1P": Entry(name: "Palm Rest Right", category: .board),
        "Ts0S": Entry(name: "Palm Rest %@", arg: "S0", category: .board),
        "Ts1S": Entry(name: "Palm Rest %@", arg: "S1", category: .board),
        "Ts2S": Entry(name: "Palm Rest %@", arg: "S2", category: .board),
        "Th1H": Entry(name: "Heat Pipe %@", arg: "1", category: .board),
        "Th2H": Entry(name: "Heat Pipe %@", arg: "2", category: .board),
        "TTLD": Entry(name: "Thunderbolt Left", category: .board),
        "TTRD": Entry(name: "Thunderbolt Right", category: .board),
        "TL0P": Entry(name: "Display Proximity", category: .board),
    ]

    /// Pure lookup, safe to call from the sampling thread.
    static func category(for key: String) -> SensorCategory {
        if let k = known[key] { return k.category }
        if intelCore(key) != nil || key.hasPrefix("Tp") || key.hasPrefix("Te") { return .cpu }
        if key.hasPrefix("Tg") { return .gpu }
        return .other
    }

    /// Localized name in the current UI language (call on the main thread).
    static func name(for key: String) -> String {
        if let k = known[key] { return k.arg.map { L(k.name, $0) } ?? L(k.name) }
        if let n = intelCore(key) { return L("CPU Core %@", "\(n)") }
        // Apple Silicon: Tp* performance cores, Te* efficiency cores, Tg* GPU
        if key.hasPrefix("Tp") { return L("CPU Performance Core %@", String(key.dropFirst(2))) }
        if key.hasPrefix("Te") { return L("CPU Efficiency Core %@", String(key.dropFirst(2))) }
        if key.hasPrefix("Tg") { return L("GPU %@", String(key.dropFirst(2))) }
        return L("Sensor %@", key)
    }

    /// Intel per-core keys: TC1C … TC9C.
    private static func intelCore(_ key: String) -> Int? {
        let c = Array(key)
        guard c.count == 4, key.hasPrefix("TC"), key.hasSuffix("C") else { return nil }
        return Int(String(c[2]))
    }
}
