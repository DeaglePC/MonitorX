#if !APPSTORE
import Foundation
import IOKit

/// Reads AppleSMC through IOKit (no root needed for reads). Not available inside the App Sandbox.
final class SMCReader {
    private var conn: io_connect_t = 0

    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    // Explicit padding: C pads this struct to 12 bytes, Swift would reuse the tail for the next field.
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var attributes: UInt8 = 0; var pad0: UInt8 = 0, pad1: UInt8 = 0, pad2: UInt8 = 0 }
    private typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                               UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct Param {
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private struct Meta { var size: UInt32; var type: UInt32 }
    private var metaCache: [UInt32: Meta] = [:]
    private var temperatureKeys: [String]?

    init?() {
        guard MemoryLayout<Param>.stride == 80 else { return nil }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    // MARK: low level

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func string(_ v: UInt32) -> String {
        String(decoding: [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)], as: UTF8.self)
    }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var outSize = MemoryLayout<Param>.stride
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<Param>.stride, &output, &outSize)
        return (r == KERN_SUCCESS && output.result == 0) ? output : nil
    }

    private func meta(_ code: UInt32) -> Meta? {
        if let m = metaCache[code] { return m }
        var input = Param()
        input.key = code
        input.data8 = 9 // read key info
        guard let out = call(&input) else { return nil }
        let m = Meta(size: out.keyInfo.dataSize, type: out.keyInfo.dataType)
        metaCache[code] = m
        return m
    }

    private func bytes(_ code: UInt32) -> (bytes: [UInt8], type: UInt32)? {
        guard let m = meta(code), m.size > 0, m.size <= 32 else { return nil }
        var input = Param()
        input.key = code
        input.keyInfo.dataSize = m.size
        input.data8 = 5 // read bytes
        guard let out = call(&input) else { return nil }
        return (withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(m.size))) }, m.type)
    }

    func value(_ key: String) -> Double? {
        guard let (b, type) = bytes(Self.fourCC(key)) else { return nil }
        switch type {
        case Self.fourCC("flt "):
            guard b.count >= 4 else { return nil }
            return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case Self.fourCC("sp78"):
            guard b.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        case Self.fourCC("fpe2"):
            guard b.count >= 2 else { return nil }
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        case Self.fourCC("ui8 "):
            return Double(b[0])
        case Self.fourCC("ui16"):
            guard b.count >= 2 else { return nil }
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case Self.fourCC("ui32"):
            guard b.count >= 4 else { return nil }
            return Double(b.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        default:
            return nil
        }
    }

    /// Every key that starts with "T" and holds a temperature-like value (enumerated once).
    private func enumerateTemperatureKeys() -> [String] {
        guard let count = value("#KEY"), count > 0 else { return [] }
        var keys: [String] = []
        for index in 0..<UInt32(count) {
            var input = Param()
            input.data8 = 8 // get key by index
            input.data32 = index
            guard let out = call(&input) else { continue }
            let name = Self.string(out.key)
            guard name.hasPrefix("T"), let m = meta(out.key),
                  m.type == Self.fourCC("sp78") || m.type == Self.fourCC("flt ") else { continue }
            keys.append(name)
        }
        return keys
    }

    // MARK: high level

    /// `all == true` reads every temperature sensor; otherwise only the few keys the overview needs.
    func readSensors(all: Bool) -> SensorInfo {
        var s = SensorInfo()

        if all {
            if temperatureKeys == nil { temperatureKeys = enumerateTemperatureKeys() }
            for key in temperatureKeys ?? [] {
                guard let v = value(key), v > 5, v < 125 else { continue }   // -127 / ~0 mean "no sensor"
                s.all.append(SensorReading(key: key, category: SensorNames.category(for: key), value: v))
            }
            s.all.sort { ($0.category.rawValue, $0.key) < ($1.category.rawValue, $1.key) }
        }

        let byKey = Dictionary(uniqueKeysWithValues: s.all.map { ($0.key, $0.value) })
        func temp(_ keys: [String]) -> [Double] {
            keys.compactMap { byKey[$0] ?? (all ? nil : value($0)) }.filter { $0 > 5 && $0 < 125 }
        }
        // Intel package/die keys, then Apple Silicon performance/efficiency core keys.
        let cpuIntel = temp(["TC0P", "TC0D", "TC0E", "TC0F", "TCXC", "TC0H"])
        let cpuARM = temp(["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0T", "Tp0X", "Tp0b", "Tp0f", "Tp0j", "Tp0n", "Te05", "Te0L"])
        if let m = cpuIntel.max() { s.cpuTemp = m }
        else if !cpuARM.isEmpty { s.cpuTemp = cpuARM.reduce(0, +) / Double(cpuARM.count) }
        s.gpuTemp = temp(["TGDD", "TG0P", "TG0D", "Tg05", "Tg0D", "Tg0L", "Tg0T"]).max()

        if let n = value("FNum"), n >= 1 {
            for i in 0..<min(Int(n), 6) {
                guard let rpm = value("F\(i)Ac") else { continue }
                let lo = value("F\(i)Mn") ?? 0
                let hi = value("F\(i)Mx") ?? max(lo, rpm)
                s.fans.append(FanReading(id: i, count: Int(n), rpm: rpm, min: lo, max: hi))
            }
        }
        return s
    }
}
#endif
