#if !APPSTORE
import Foundation
import Darwin

/// Samples every process on the system.
/// - libproc (`proc_pid_rusage`) gives accurate footprint / CPU time / disk IO for processes we may inspect.
/// - `ps` fills in the ones that need root (WindowServer, coreaudiod, …) using RSS and cumulative CPU time.
final class ProcessSampler {
    private struct Prev { var cpuNs: UInt64; var diskR: UInt64; var diskW: UInt64 }
    private struct Meta { var name: String; var path: String }

    private var prev: [Int32: Prev] = [:]
    private var prevTime: UInt64 = 0
    private var meta: [Int32: Meta] = [:]
    private var timebase = mach_timebase_info_data_t()

    init() { mach_timebase_info(&timebase) }

    func sample() -> [ProcessEntry] {
        let now = DispatchTime.now().uptimeNanoseconds
        let dt = prevTime > 0 ? Double(now - prevTime) / 1e9 : 0

        // 1. all pids
        let cap = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: max(cap, 256))
        let n = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        let pidList = pids.prefix(max(0, n)).filter { $0 > 0 }

        var cur: [Int32: Prev] = [:]
        var entries: [ProcessEntry] = []
        var inaccessible = Set<Int32>()

        for pid in pidList {
            var ri = rusage_info_v4()
            let r = withUnsafeMutablePointer(to: &ri) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard r == 0 else { inaccessible.insert(pid); continue }

            let cpuNs = (ri.ri_user_time &+ ri.ri_system_time) &* UInt64(timebase.numer) / UInt64(max(1, timebase.denom))
            let m = metaFor(pid)
            var e = Self.makeEntry(pid: pid, name: m.name, path: m.path)
            e.mem = ri.ri_phys_footprint
            cur[pid] = Prev(cpuNs: cpuNs, diskR: ri.ri_diskio_bytesread, diskW: ri.ri_diskio_byteswritten)
            if dt > 0, let p = prev[pid] {
                e.cpu = Double(cpuNs &- p.cpuNs) / 1e9 / dt * 100
                e.diskRead = Double(ri.ri_diskio_bytesread &- p.diskR) / dt
                e.diskWrite = Double(ri.ri_diskio_byteswritten &- p.diskW) / dt
            }
            entries.append(e)
        }

        // 2. root / other-user processes via ps
        if !inaccessible.isEmpty {
            for row in Self.runPS() where inaccessible.contains(row.pid) {
                var e = Self.makeEntry(pid: row.pid, name: Self.baseName(row.path), path: row.path)
                e.mem = row.rssBytes
                cur[row.pid] = Prev(cpuNs: row.cpuNs, diskR: 0, diskW: 0)
                if dt > 0, let p = prev[row.pid] {
                    e.cpu = Double(row.cpuNs &- p.cpuNs) / 1e9 / dt * 100
                }
                entries.append(e)
            }
        }

        prev = cur
        prevTime = now
        let alive = Set(pidList)
        meta = meta.filter { alive.contains($0.key) }
        return entries
    }

    // MARK: helpers

    private func metaFor(_ pid: Int32) -> Meta {
        if let m = meta[pid] { return m }
        var pathBuf = [CChar](repeating: 0, count: 4096)
        let pl = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        let path = pl > 0 ? String(cString: pathBuf) : ""
        var nameBuf = [CChar](repeating: 0, count: 64)
        proc_name(pid, &nameBuf, UInt32(nameBuf.count))
        let short = String(cString: nameBuf)
        let base = Self.baseName(path)
        let m = Meta(name: base.isEmpty ? (short.isEmpty ? "pid \(pid)" : short) : base, path: path)
        meta[pid] = m
        return m
    }

    static func baseName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    static func makeEntry(pid: Int32, name: String, path: String) -> ProcessEntry {
        var groupKey = name
        var groupName = name
        var appPath: String?
        if let r = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) {
            let app = String(path[path.startIndex..<r.upperBound]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let full = "/" + app
            appPath = full
            groupName = ((full as NSString).lastPathComponent as NSString).deletingPathExtension
            groupKey = full
        }
        if pid == 0 { groupKey = "kernel_task"; groupName = "kernel_task" }
        return ProcessEntry(pid: pid, name: name, groupKey: groupKey, groupName: groupName, appPath: appPath)
    }

    private struct PSRow { var pid: Int32; var rssBytes: UInt64; var cpuNs: UInt64; var path: String }

    private static func runPS() -> [PSRow] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,rss=,cputime=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var rows: [PSRow] = []
        for line in text.split(separator: "\n") {
            // pid rss cputime comm...
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let rss = UInt64(parts[1]) else { continue }
            rows.append(PSRow(pid: pid, rssBytes: rss * 1024, cpuNs: parseCPUTime(String(parts[2])), path: String(parts[3])))
        }
        return rows
    }

    /// "412:39.61", "1:02:03.45" or "2-01:02:03"
    private static func parseCPUTime(_ s: String) -> UInt64 {
        var days = 0.0
        var rest = Substring(s)
        if let dash = rest.firstIndex(of: "-") {
            days = Double(rest[rest.startIndex..<dash]) ?? 0
            rest = rest[rest.index(after: dash)...]
        }
        var seconds = 0.0
        for comp in rest.split(separator: ":") {
            seconds = seconds * 60 + (Double(comp) ?? 0)
        }
        return UInt64((days * 86400 + seconds) * 1e9)
    }
}

// MARK: - per-process network (netstat)

/// Per-process network throughput from `netstat -anv`, which lists every socket with its cumulative rx/tx bytes
/// and owning pid. ~4x cheaper than `nettop` (which pins >1 core while running). Loopback sockets are ignored so
/// numbers reflect real interface traffic (a local proxy would otherwise be counted twice).
final class NetstatSampler {
    typealias Rates = [Int32: (name: String, inRate: Double, outRate: Double)]

    private var prev: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var prevTime: UInt64 = 0

    func reset() { prev = [:]; prevTime = 0 }

    func sample() -> Rates {
        let now = DispatchTime.now().uptimeNanoseconds
        let dt = prevTime > 0 ? Double(now - prevTime) / 1e9 : 0
        var cur: [String: (rx: UInt64, tx: UInt64)] = [:]
        var acc: [Int32: (name: String, rx: UInt64, tx: UInt64)] = [:]

        for proto in ["tcp", "udp"] {
            for line in Self.run(proto).split(separator: "\n") {
                guard let s = Self.parse(line) else { continue }
                let id = proto + s.id
                cur[id] = (s.rx, s.tx)
                guard dt > 0, !s.loopback else { continue }
                let (drx, dtx): (UInt64, UInt64)
                if let p = prev[id] {
                    drx = s.rx >= p.rx ? s.rx - p.rx : 0
                    dtx = s.tx >= p.tx ? s.tx - p.tx : 0
                } else {
                    drx = s.rx; dtx = s.tx      // socket created since last sample
                }
                if drx == 0 && dtx == 0 { continue }
                var e = acc[s.pid] ?? (s.name, 0, 0)
                e.rx += drx; e.tx += dtx
                acc[s.pid] = e
            }
        }
        prev = cur
        prevTime = now
        guard dt > 0 else { return [:] }
        return acc.mapValues { ($0.name, Double($0.rx) / dt, Double($0.tx) / dt) }
    }

    private struct Sock { var pid: Int32; var name: String; var rx: UInt64; var tx: UInt64; var id: String; var loopback: Bool }

    private static func parse(_ line: Substring) -> Sock? {
        guard line.hasPrefix("tcp") || line.hasPrefix("udp") else { return nil }
        let t = line.split(separator: " ", omittingEmptySubsequences: true)
        guard t.count >= 15 else { return nil }
        // Trailing columns after "process:pid": state options gencnt flags flags1 usecnt rtncnt fltrs (8 tokens).
        let procEnd = t.count - 9
        // TCP has a state column before rxbytes; UDP does not.
        let hasState = t[5].first?.isLetter == true
        let rxIdx = hasState ? 6 : 5
        let procStart = rxIdx + 4
        guard procEnd >= procStart,
              let rx = UInt64(t[rxIdx]), let tx = UInt64(t[rxIdx + 1]),
              let colon = t[procEnd].lastIndex(of: ":"),
              let pid = Int32(t[procEnd][t[procEnd].index(after: colon)...]), pid > 0 else { return nil }

        var nameParts = t[procStart...procEnd].map(String.init)
        nameParts[nameParts.count - 1] = String(t[procEnd][t[procEnd].startIndex..<colon])
        let name = nameParts.joined(separator: " ")

        func host(_ s: Substring) -> Substring { s.lastIndex(of: ".").map { s[s.startIndex..<$0] } ?? s }
        let local = host(t[3]), foreign = host(t[4])
        let loop = foreign.hasPrefix("127.") || foreign == "::1" || foreign.hasPrefix("fe80::1%lo0") || (local == foreign && foreign != "*")
        return Sock(pid: pid, name: name, rx: rx, tx: tx, id: String(t[t.count - 6]), loopback: loop)
    }

    private static func run(_ proto: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        p.arguments = ["-anv", "-p", proto]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
#endif
