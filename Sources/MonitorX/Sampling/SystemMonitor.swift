import Foundation
import Observation

@Observable
final class SystemMonitor {
    static let historyCapacity = 60

    // Published state (main thread)
    var cpu = CPUStats()
    var mem = MemStats()
    var net = NetStats()
    var disk = DiskStats()
    var battery: BatteryInfo?
    var sensors = SensorInfo()
    var hardware = HardwareLoader.quick()

    var cpuHistory: [Double] = []
    var memHistory: [Double] = []
    var netDownHistory: [Double] = []
    var netUpHistory: [Double] = []
    var diskReadHistory: [Double] = []
    var diskWriteHistory: [Double] = []

    /// Empty in the App Store edition (the sandbox does not allow inspecting other processes).
    var groups: [ProcessGroup] = []
    var processesReady = false

    /// Called on the main thread after every system sample (used to refresh the menu-bar image).
    @ObservationIgnored var onUpdate: (() -> Void)?

    // Background state
    @ObservationIgnored private let queue = DispatchQueue(label: "monitorx.sampler", qos: .utility)
    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private let cpuSampler = CPUSampler()
    @ObservationIgnored private let memSampler = MemorySampler()
    @ObservationIgnored private let netSampler = NetworkSampler()
    @ObservationIgnored private let diskSampler = DiskSampler()
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var detailActive = false
    @ObservationIgnored private var menuBarSensors = false

    #if !APPSTORE
    @ObservationIgnored private let procSampler = ProcessSampler()
    @ObservationIgnored private let netstat = NetstatSampler()
    @ObservationIgnored private let smc = SMCReader()
    @ObservationIgnored private var detailTimer: DispatchSourceTimer?
    @ObservationIgnored private var latestEntries: [ProcessEntry] = []
    @ObservationIgnored private var latestNet: NetstatSampler.Rates = [:]
    #endif

    init() {
        // system_profiler / registry lookups are slow; fill in model, GPU, serial asynchronously.
        let base = hardware
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let full = HardwareLoader.detailed(base: base)
            DispatchQueue.main.async { self?.hardware = full }
        }
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    /// The detail panel is on screen: sample sensors every tick and processes every 3 s.
    func setDetailActive(_ active: Bool) {
        queue.async { [self] in
            guard detailActive != active else { return }
            detailActive = active
            #if !APPSTORE
            detailTimer?.cancel()
            detailTimer = nil
            if active {
                _ = procSampler.sample()          // baselines for the rate calculations
                netstat.reset(); _ = netstat.sample()
                let t = DispatchSource.makeTimerSource(queue: queue)
                t.schedule(deadline: .now() + 1.0, repeating: .seconds(3), leeway: .milliseconds(200))
                t.setEventHandler { [weak self] in self?.sampleProcesses() }
                detailTimer = t
                t.resume()
            } else {
                latestNet = [:]
            }
            #endif
        }
    }

    /// The menu bar shows a temperature or fan speed: read the (few, cheap) overview sensors every tick.
    func setMenuBarSensors(_ on: Bool) {
        queue.async { [self] in menuBarSensors = on }
    }

    func shutdown() {}

    // MARK: sampling

    private func tick() {
        tickCount += 1
        let cpu = cpuSampler.sample()
        let mem = memSampler.sample()
        let net = netSampler.sample()
        let disk = diskSampler.sample()
        var battery: BatteryInfo?? = nil
        var sensors: SensorInfo? = nil
        // Battery / sensors change slowly, except while the panel is open.
        let slowTick = detailActive || tickCount % 3 == 1
        if slowTick {
            battery = .some(BatteryReader.read())
        }
        #if !APPSTORE
        if slowTick || menuBarSensors {
            sensors = smc?.readSensors(all: detailActive)
        }
        #endif

        DispatchQueue.main.async { [self] in
            self.cpu = cpu; self.mem = mem; self.net = net; self.disk = disk
            if let battery { self.battery = battery }
            if let sensors { self.sensors = sensors }
            push(&cpuHistory, cpu.total)
            push(&memHistory, mem.usedFraction)
            push(&netDownHistory, net.downRate)
            push(&netUpHistory, net.upRate)
            push(&diskReadHistory, disk.readRate)
            push(&diskWriteHistory, disk.writeRate)
            onUpdate?()
        }
    }

    #if !APPSTORE
    private func sampleProcesses() {
        guard detailActive else { return }
        latestEntries = procSampler.sample()
        latestNet = netstat.sample()
        publishGroups()
    }

    private func publishGroups() {
        guard detailActive else { return }
        var byKey: [String: ProcessGroup] = [:]
        var known = Set<Int32>()
        // Some processes (e.g. a browser whose bundle was updated on disk) have no readable path; fold them into
        // the app whose main executable shares their name.
        var appByName: [String: (key: String, path: String)] = [:]
        for e in latestEntries where e.appPath != nil && e.name == e.groupName { appByName[e.name] = (e.groupKey, e.appPath!) }
        for var e in latestEntries {
            known.insert(e.pid)
            if e.appPath == nil, let app = appByName[e.name] { e.groupKey = app.key; e.appPath = app.path }
            if let r = latestNet[e.pid] { e.netIn = r.inRate; e.netOut = r.outRate }
            byKey[e.groupKey, default: ProcessGroup(id: e.groupKey, name: e.groupName, appPath: e.appPath, members: [])].members.append(e)
        }
        // Network-only processes we couldn't otherwise see.
        for (pid, r) in latestNet where !known.contains(pid) {
            var e = ProcessSampler.makeEntry(pid: pid, name: r.name, path: "")
            e.netIn = r.inRate; e.netOut = r.outRate
            byKey[e.groupKey, default: ProcessGroup(id: e.groupKey, name: e.groupName, appPath: nil, members: [])].members.append(e)
        }
        let result = Array(byKey.values)
        DispatchQueue.main.async { [self] in
            groups = result
            processesReady = true
        }
    }
    #endif

    private func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > Self.historyCapacity { arr.removeFirst(arr.count - Self.historyCapacity) }
    }

    // MARK: queries used by the UI

    /// Top groups (or individual processes when `grouped == false`) by a metric.
    func top(_ metric: ProcMetric, grouped: Bool, limit: Int) -> [ProcessGroup] {
        let source: [ProcessGroup]
        if grouped {
            source = groups
        } else {
            source = groups.flatMap { g in
                g.members.map { ProcessGroup(id: "\(g.id)#\($0.pid)", name: $0.name, appPath: g.appPath, members: [$0]) }
            }
        }
        return source
            .filter { $0.value(metric) >= Self.minVisible(metric) }
            .sorted { $0.value(metric) > $1.value(metric) }
            .prefix(limit)
            .map { $0 }
    }

    private static func minVisible(_ m: ProcMetric) -> Double {
        switch m {
        case .cpu: 0.05
        case .memory: 1
        case .network: 64          // B/s
        case .disk: 1024           // B/s
        }
    }

    func topOne(_ metric: ProcMetric) -> ProcessGroup? {
        groups.max { $0.value(metric) < $1.value(metric) }.flatMap { $0.value(metric) >= Self.minVisible(metric) ? $0 : nil }
    }
}
