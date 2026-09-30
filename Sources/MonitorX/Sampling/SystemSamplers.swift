import Foundation
import Darwin
import IOKit

// MARK: - CPU

final class CPUSampler {
    private var prev: [[UInt32]] = []

    func sample() -> CPUStats {
        var numCPU: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPU, &info, &infoCount) == KERN_SUCCESS,
              let info else { return CPUStats() }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let states = Int(CPU_STATE_MAX)
        var cur: [[UInt32]] = []
        for i in 0..<Int(numCPU) {
            cur.append((0..<states).map { UInt32(bitPattern: info[states * i + $0]) })
        }
        defer { prev = cur }

        var stats = CPUStats()
        guard prev.count == cur.count else { return stats }

        var tUser = 0.0, tSys = 0.0, tIdle = 0.0
        for i in 0..<cur.count {
            let u = Double(cur[i][Int(CPU_STATE_USER)] &- prev[i][Int(CPU_STATE_USER)])
            let s = Double(cur[i][Int(CPU_STATE_SYSTEM)] &- prev[i][Int(CPU_STATE_SYSTEM)])
            let n = Double(cur[i][Int(CPU_STATE_NICE)] &- prev[i][Int(CPU_STATE_NICE)])
            let d = Double(cur[i][Int(CPU_STATE_IDLE)] &- prev[i][Int(CPU_STATE_IDLE)])
            let all = u + s + n + d
            stats.perCore.append(all > 0 ? (u + s + n) / all : 0)
            tUser += u + n; tSys += s; tIdle += d
        }
        let all = tUser + tSys + tIdle
        if all > 0 {
            stats.user = tUser / all
            stats.system = tSys / all
            stats.total = (tUser + tSys) / all
        }
        var l = [Double](repeating: 0, count: 3)
        getloadavg(&l, 3)
        stats.load = (l[0], l[1], l[2])
        return stats
    }
}

// MARK: - Memory

final class MemorySampler {
    let total: UInt64 = {
        var v: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &v, &size, nil, 0)
        return v
    }()

    func sample() -> MemStats {
        var s = MemStats()
        s.total = total

        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(vm.internal_page_count)
            let purgeable = UInt64(vm.purgeable_count)
            s.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            s.wired = UInt64(vm.wire_count) * page
            s.compressed = UInt64(vm.compressor_page_count) * page
            s.cached = (UInt64(vm.external_page_count) + purgeable) * page
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            s.swapUsed = swap.xsu_used
            s.swapTotal = swap.xsu_total
        }

        var level: Int32 = 1
        var lsize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &lsize, nil, 0) == 0 {
            s.pressure = Int(level)
        }
        return s
    }
}

// MARK: - Network

final class NetworkSampler {
    private var prevRaw: [String: (UInt32, UInt32)] = [:]
    private var prevTime: UInt64 = 0
    private var totalDown: UInt64 = 0
    private var totalUp: UInt64 = 0

    func sample() -> NetStats {
        var stats = NetStats()
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return stats }
        defer { freeifaddrs(ifap) }

        let now = DispatchTime.now().uptimeNanoseconds
        var dIn: UInt64 = 0, dOut: UInt64 = 0
        var raws: [String: (UInt32, UInt32)] = [:]
        var ipByIface: [String: String] = [:]

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let name = String(cString: p.pointee.ifa_name)
            guard name.hasPrefix("en"), let addr = p.pointee.ifa_addr else { continue }
            let flags = Int32(p.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            if addr.pointee.sa_family == UInt8(AF_LINK), let data = p.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                raws[name] = (d.ifi_ibytes, d.ifi_obytes)
            } else if addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if !ip.hasPrefix("169.254") { ipByIface[name] = ip }
                }
            }
        }

        for (name, cur) in raws {
            if let old = prevRaw[name] {
                dIn += UInt64(cur.0 &- old.0)   // wrap-safe for 32-bit counters
                dOut += UInt64(cur.1 &- old.1)
            }
        }
        if prevTime > 0 {
            let dt = Double(now - prevTime) / 1e9
            if dt > 0 {
                stats.downRate = Double(dIn) / dt
                stats.upRate = Double(dOut) / dt
            }
        }
        totalDown += dIn; totalUp += dOut
        prevRaw = raws; prevTime = now
        stats.totalDown = totalDown
        stats.totalUp = totalUp

        // Primary interface: the one that has an IPv4 address (prefer en0).
        let candidates = ipByIface.keys.sorted()
        if let iface = candidates.contains("en0") ? "en0" : candidates.first {
            stats.interface = iface
            stats.ip = ipByIface[iface] ?? "—"
        }
        return stats
    }
}

// MARK: - Disk

final class DiskSampler {
    private var prev: (read: UInt64, write: UInt64)?
    private var prevTime: UInt64 = 0

    func sample() -> DiskStats {
        var stats = DiskStats()
        stats.volumes = Self.volumes()

        let io = Self.ioBytes()
        let now = DispatchTime.now().uptimeNanoseconds
        if let p = prev, prevTime > 0 {
            let dt = Double(now - prevTime) / 1e9
            if dt > 0 {
                stats.readRate = Double(io.read &- p.read) / dt
                stats.writeRate = Double(io.write &- p.write) / dt
            }
        }
        prev = io; prevTime = now
        return stats
    }

    static func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeIsInternalKey, .volumeIsLocalKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                               options: [.skipHiddenVolumes]) else { return [] }
        var result: [VolumeInfo] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsLocal == true,
                  let total = v.volumeTotalCapacity, total > 0 else { continue }
            let free = v.volumeAvailableCapacityForImportantUsage ?? 0
            result.append(VolumeInfo(path: url.path,
                                     name: v.volumeName ?? url.lastPathComponent,
                                     total: UInt64(total), free: UInt64(max(0, free)),
                                     isInternal: v.volumeIsInternal ?? false))
        }
        // Boot volume first.
        return result.sorted { ($0.path == "/" ? 0 : 1, $0.path) < ($1.path == "/" ? 0 : 1, $1.path) }
    }

    static func ioBytes() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, write: UInt64 = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let s = dict["Statistics"] as? [String: Any] {
                read += (s["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (s["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return (read, write)
    }
}
