import Foundation
import IOKit

/// Reads CPU and GPU power from the private IOReport "Energy Model" channels.
/// Bound at runtime via dlopen so we never link the private framework at build time.
/// All use is confined to the main actor by its owner (`PowerMonitor`).
final class IOReportPower {
    private typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSub = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> Unmanaged<AnyObject>?
    private typealias CreateSamples = @convention(c) (AnyObject?, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias IterateFn = @convention(c) (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Int32
    private typealias ChanStr = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleInt = @convention(c) (CFDictionary, Int32) -> Int64

    /// No CPU or GPU cluster in a shipping Mac comes near this. A reading above it
    /// is a counter glitch, not real power (issue #4: a ~1,900 W CPU spike).
    static let maximumPlausibleWatts: Double = 500

    /// Never compute a rate over a window shorter than this, whatever the caller asks.
    static let absoluteMinimumInterval: TimeInterval = 0.25

    /// How long the last CPU reading stays on screen while the CPU counter does
    /// not move. Some chips publish energy in batches every ~2 s, so one or two
    /// still ticks are normal. On macOS 27 the "Energy Model" CPU counter freezes
    /// for minutes (vladkens/macmon#76); past this limit CPU power reads as
    /// unavailable instead of a false 0 W.
    static let stalledHoldLimit: TimeInterval = 6

    /// What to do with one IOReport delta.
    enum Evaluation: Equatable {
        /// Plausible reading: publish it and advance the baseline.
        case accept(cpu: Double?, gpu: Double?)
        /// Window too short to give a stable rate: keep the old baseline and
        /// measure again next tick over the longer window.
        case keepBaseline
        /// Counter went backwards or produced an impossible rate: drop the
        /// reading and start a fresh baseline from the current sample.
        case rebase
    }

    private let copyChannels: CopyChannels
    private let createSub: CreateSub
    private let createSamples: CreateSamples
    private let createDelta: CreateDelta
    private let iterate: IterateFn
    private let chanName: ChanStr
    private let getUnit: ChanStr
    private let simpleInt: SimpleInt
    private let chanGroup: ChanStr?

    private let subscription: AnyObject
    private let channels: CFMutableDictionary
    /// True when the subscription includes the macOS 27 CLPC energy counters.
    let hasCLPCChannels: Bool
    private var previous: CFDictionary?
    private var previousUptime: TimeInterval = 0
    /// Time the CPU counter has gone without moving, and the last reading shown.
    private var cpuStalledFor: TimeInterval = 0
    private var lastCpuWatts: Double?

    init?() {
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return nil }
        func bind<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let cc = bind("IOReportCopyChannelsInGroup", CopyChannels.self),
              let cs = bind("IOReportCreateSubscription", CreateSub.self),
              let csa = bind("IOReportCreateSamples", CreateSamples.self),
              let cd = bind("IOReportCreateSamplesDelta", CreateDelta.self),
              let it = bind("IOReportIterate", IterateFn.self),
              let cn = bind("IOReportChannelGetChannelName", ChanStr.self),
              let gu = bind("IOReportChannelGetUnitLabel", ChanStr.self),
              let si = bind("IOReportSimpleGetIntegerValue", SimpleInt.self) else { return nil }
        copyChannels = cc; createSub = cs; createSamples = csa; createDelta = cd
        iterate = it; chanName = cn; getUnit = gu; simpleInt = si
        chanGroup = bind("IOReportChannelGetGroup", ChanStr.self)

        guard let chans = cc("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
              let mut = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, chans) else { return nil }

        // macOS 27: also subscribe to the AppleCLPC energy counters, which keep
        // counting where the Energy Model's CPU counter freezes. They need the
        // group getter to be told apart from the Energy Model channels.
        if chanGroup != nil, let extended = Self.addingCLPCChannels(to: chans) {
            var subbed: Unmanaged<CFMutableDictionary>?
            if let sub = cs(nil, extended, &subbed, 0, nil)?.takeRetainedValue() {
                channels = extended
                subscription = sub
                hasCLPCChannels = true
                return
            }
        }
        // Energy Model only: macOS 26 and older, an unknown CLPC driver, or a
        // subscription that IOReport refused with the CLPC channels in it.
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = cs(nil, mut, &subbed, 0, nil)?.takeRetainedValue() else { return nil }
        channels = mut
        subscription = sub
        hasCLPCChannels = false
    }

    /// The Energy Model channel set plus one CLPC descriptor per known counter,
    /// or nil when this Mac has none (other macOS version, unknown driver).
    private static func addingCLPCChannels(to energyModel: CFDictionary) -> CFMutableDictionary? {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        var descriptors: [NSMutableDictionary] = []
        for driver in CLPCEnergyChannels.liveDrivers() {
            guard let found = CLPCEnergyChannels.channels(bundle: driver.bundle, osMajor: major) else { continue }
            descriptors += found.map { CLPCEnergyChannels.descriptor(driverID: driver.id, channel: $0) }
        }
        guard !descriptors.isEmpty else { return nil }
        let copy = NSMutableDictionary(dictionary: energyModel as NSDictionary)
        let list = NSMutableArray(array: (copy[CLPCEnergyChannels.channelListKey] as? NSArray) ?? NSArray())
        descriptors.forEach { list.add($0) }
        copy[CLPCEnergyChannels.channelListKey] = list
        return copy as CFMutableDictionary
    }

    /// Forget the baseline, e.g. after the system wakes from sleep. The next
    /// call only records a new baseline.
    func reset() {
        previous = nil
        previousUptime = 0
        cpuStalledFor = 0
        lastCpuWatts = nil
    }

    /// Returns (cpu, gpu) watts. Components are nil when unavailable: on the
    /// first call, whenever a reading is rejected as implausible, and for the CPU
    /// while its counter is frozen. `systemWatts` is the SMC system total, used
    /// to recognise a CPU or GPU reading far above what the whole Mac draws.
    func sample(minimumInterval: TimeInterval = 1, systemWatts: Double? = nil) -> (cpu: Double?, gpu: Double?) {
        let start = ProcessInfo.processInfo.systemUptime
        guard let current = createSamples(subscription, channels, nil)?.takeRetainedValue() else {
            return (nil, nil)
        }
        // Time the sample at the middle of the call rather than after it returns,
        // so a slow IOReport call does not stretch or shrink the window.
        let now = (start + ProcessInfo.processInfo.systemUptime) / 2
        guard let prev = previous else {
            previous = current; previousUptime = now
            return (nil, nil)
        }
        let elapsed = now - previousUptime
        if elapsed > 0, elapsed < Self.effectiveMinimumInterval(minimumInterval) {
            return (nil, nil) // keep the baseline; the next tick measures a longer window
        }
        guard let delta = createDelta(prev, current, nil)?.takeRetainedValue() else {
            previous = current; previousUptime = now
            return (nil, nil)
        }

        var model = EnergyReading(), clpc = EnergyReading()
        _ = iterate(delta) { [self] channel in
            let name = (chanName(channel)?.takeUnretainedValue()).map { $0 as String } ?? ""
            let unit = (getUnit(channel)?.takeUnretainedValue()).map { $0 as String } ?? ""
            let group = (chanGroup?(channel)?.takeUnretainedValue()).map { $0 as String } ?? ""
            let raw = simpleInt(channel, 0)
            let joules = IOReportPower.energyToJoules(raw: raw, unit: unit)
            if group == CLPCEnergyChannels.groupName {
                // Described as nanojoules in the descriptor, so do not depend on
                // the label IOReport derives for a hand-built channel.
                let clpcJoules = Double(raw) / 1e9
                if name == CLPCEnergyChannels.cpuName { clpc.addCPU(clpcJoules) }
                else if name == CLPCEnergyChannels.gpuName { clpc.addGPU(clpcJoules) }
            } else if name.hasSuffix("CPU Energy") {
                // Roll-up channels only. Ultra chips name theirs "DIE_n_CPU Energy".
                // Never match by substring: per-core and SRAM sub-channels would be
                // counted on top of the roll-up (lablup/all-smi#410).
                model.addCPU(joules)
            } else if name == "GPU Energy" {
                model.addGPU(joules)
            }
            return 0
        }
        let reading = Self.preferred(clpc: clpc, energyModel: model)
        let sawCPU = reading.cpu != nil

        switch Self.evaluate(cpuJoules: reading.cpu,
                             gpuJoules: reading.gpu,
                             elapsed: elapsed, minimumInterval: minimumInterval,
                             cpuStalledFor: cpuStalledFor, systemWatts: systemWatts) {
        case .accept(let cpu, let gpu):
            previous = current; previousUptime = now
            if sawCPU, cpu == nil {
                // Counter did not move: hold the last reading briefly, then report none.
                cpuStalledFor += elapsed
                if cpuStalledFor > Self.stalledHoldLimit { lastCpuWatts = nil }
            } else {
                cpuStalledFor = 0
                lastCpuWatts = cpu
            }
            return (lastCpuWatts, gpu)
        case .keepBaseline:
            return (nil, nil)
        case .rebase:
            previous = current; previousUptime = now
            cpuStalledFor = 0
            lastCpuWatts = nil
            return (nil, nil)
        }
    }

    /// Joules seen in one delta from one source; nil where the source has no channel.
    struct EnergyReading: Equatable {
        var cpu: Double?
        var gpu: Double?
        mutating func addCPU(_ joules: Double) { cpu = (cpu ?? 0) + joules }
        mutating func addGPU(_ joules: Double) { gpu = (gpu ?? 0) + joules }
    }

    /// CLPC counters win wherever they delivered a value; the Energy Model fills
    /// in the rest. This is macmon's order on macOS 27.
    static func preferred(clpc: EnergyReading, energyModel: EnergyReading) -> EnergyReading {
        EnergyReading(cpu: clpc.cpu ?? energyModel.cpu, gpu: clpc.gpu ?? energyModel.gpu)
    }

    /// The most a CPU or GPU reading may be before it counts as a counter glitch.
    /// With a known system total the limit is 10× that total + 100 W, the rule
    /// macmon uses (vladkens/macmon#142): the SMC total lags real load steps, so
    /// a tighter limit would drop genuine readings.
    static func ceilingWatts(systemWatts: Double?) -> Double {
        guard let total = systemWatts, total.isFinite, total > 0 else { return maximumPlausibleWatts }
        return min(maximumPlausibleWatts, 10 * total + 100)
    }

    static func effectiveMinimumInterval(_ requested: TimeInterval) -> TimeInterval {
        max(absoluteMinimumInterval, requested.isFinite ? requested : 0)
    }

    /// Turn one energy delta into watts, or decide that it cannot be trusted.
    ///
    /// A CPU delta of exactly zero is not 0 W: the CPU is running this code, so
    /// it means the counter did not move (batched publication, or the macOS 27
    /// freeze). It comes back as `cpu: nil`. When the counter moves again its
    /// energy covers the stalled time too, so it is averaged over
    /// `elapsed + cpuStalledFor`. A GPU delta of zero is a real reading: an idle
    /// GPU can be powered down.
    static func evaluate(cpuJoules: Double?, gpuJoules: Double?,
                         elapsed: TimeInterval, minimumInterval: TimeInterval,
                         cpuStalledFor: TimeInterval = 0, systemWatts: Double? = nil) -> Evaluation {
        guard elapsed.isFinite, elapsed > 0 else { return .rebase }
        guard elapsed >= effectiveMinimumInterval(minimumInterval) else { return .keepBaseline }
        let joules = [cpuJoules, gpuJoules].compactMap { $0 }
        // A negative or non-finite delta means the counter was reset or wrapped.
        if joules.contains(where: { !$0.isFinite || $0 < 0 }) { return .rebase }
        let cpuWindow = elapsed + max(0, cpuStalledFor)
        let cpu = cpuJoules.flatMap { $0 == 0 ? nil : $0 / cpuWindow }
        let gpu = gpuJoules.map { $0 / elapsed }
        let ceiling = ceilingWatts(systemWatts: systemWatts)
        if [cpu, gpu].compactMap({ $0 }).contains(where: { $0 > ceiling }) { return .rebase }
        return .accept(cpu: cpu, gpu: gpu)
    }

    /// Convert an IOReport energy counter (with its unit label) to joules.
    /// IOReport reports different units per channel (e.g. CPU in mJ, GPU in nJ).
    static func energyToJoules(raw: Int64, unit: String) -> Double {
        let u = unit.lowercased()
        if u.contains("nj") { return Double(raw) / 1e9 }
        if u.contains("uj") || u.contains("µj") { return Double(raw) / 1e6 }
        if u.contains("mj") { return Double(raw) / 1e3 }
        return Double(raw)
    }
}

/// AppleCLPC energy counters: the CPU and GPU power source on macOS 27, where the
/// "Energy Model" CPU counter freezes without an Apple entitlement.
///
/// IOReport does not list these channels, so each one is described to it by hand
/// from the live driver's registry ID and a per-driver report ID. The report IDs
/// are `(table index << 32) | key`. Both parts come from the macOS 27 kernel
/// (27.0 to 27.2.1 are identical) and can move in a new major macOS, so the table
/// applies to macOS 27 only; any other version uses the Energy Model.
///
/// Table and descriptor layout ported from macmon's `src/clpc.rs` and
/// `src/sources.rs` (https://github.com/vladkens/macmon), MIT License,
/// Copyright (c) 2024 vladkens. See THIRD-PARTY-NOTICES.md.
enum CLPCEnergyChannels {
    struct Channel: Equatable, Sendable {
        let id: UInt64
        let name: String
    }

    static let groupName = "CLPC"
    static let cpuName = "CPU Energy"
    static let gpuName = "GPU Energy"
    static let channelListKey = "IOReportChannels"

    static let supportedOSMajor = 27
    private static let cpuIndex: UInt64 = 16
    private static let gpuIndex: UInt64 = 25

    /// Driver bundle ID → keys of its aggregate CPU and GPU counters (both dies on Ultra).
    private static let keys: [String: (cpu: UInt32, gpu: UInt32)] = [
        "com.apple.driver.AppleT6000CLPCv3": (0x4747_9059, 0x4519_bf1e),
        "com.apple.driver.AppleT6002CLPC": (0xb501_816b, 0x9e2c_3e8b),
        "com.apple.driver.AppleT6020CLPC": (0xe301_cd75, 0x8f34_cc7a),
        "com.apple.driver.AppleT6022CLPC": (0x76f5_fd21, 0x9062_4499),
        "com.apple.driver.AppleT6030CLPC": (0xbe03_a01a, 0x472d_6c9c),
        "com.apple.driver.AppleT6031CLPC": (0xd81e_0084, 0x1085_f98b),
        "com.apple.driver.AppleT6032CLPC": (0xf4a2_1308, 0x85e8_0513),
        "com.apple.driver.AppleT6041CLPC": (0x263c_f1f0, 0x22e4_cf59),
        "com.apple.driver.AppleT6050CLPC": (0xd3ab_60bb, 0x27cd_4ce5),
        "com.apple.driver.AppleT6050dCLPC": (0x18b3_010e, 0xedec_a11a),
        "com.apple.driver.AppleT8103CLPCv3": (0x2cdd_31f2, 0x21be_cf42),
        "com.apple.driver.AppleT8112CLPC": (0xb543_5137, 0x638d_9d52),
        "com.apple.driver.AppleT8122CLPC": (0x54b5_1c99, 0xce2d_d9dc),
        "com.apple.driver.AppleT8132CLPC": (0x4a85_4d94, 0x3b3e_3b79),
        "com.apple.driver.AppleT8140CLPC": (0x9bf5_4436, 0xef70_589c),
        "com.apple.driver.AppleT8142CLPC": (0x4370_8744, 0x6a01_0933),
        "com.apple.driver.AppleT8152CLPC": (0x485d_4bfc, 0x1178_4654),
    ]

    static var knownBundles: [String] { keys.keys.sorted() }

    static func reportID(index: UInt64, key: UInt32) -> UInt64 {
        (index << 32) | UInt64(key)
    }

    /// The CPU and GPU channels of one driver, or nil when the driver or the
    /// macOS version is not in the table.
    static func channels(bundle: String, osMajor: Int) -> [Channel]? {
        guard osMajor == supportedOSMajor, let key = keys[bundle] else { return nil }
        return [
            Channel(id: reportID(index: cpuIndex, key: key.cpu), name: cpuName),
            Channel(id: reportID(index: gpuIndex, key: key.gpu), name: gpuName),
        ]
    }

    /// An IOReport channel description for one counter. Mutable, because
    /// IOReport's getters cache derived fields in it.
    static func descriptor(driverID: UInt64, channel: Channel) -> NSMutableDictionary {
        // IOReportTypes.h: simple integer format, power category, one element.
        let channelType: Int64 = 1 | (2 << 16) | (1 << 32)
        // Energy quantity (3) scaled to nanojoules (118).
        let unit: Int64 = (3 << 56) | (118 << 32)
        let legend: [Any] = [
            NSNumber(value: Int64(bitPattern: channel.id)),
            NSNumber(value: channelType),
            channel.name,
        ]
        return NSMutableDictionary(dictionary: [
            "DriverID": NSNumber(value: Int64(bitPattern: driverID)),
            "DriverName": "AppleCLPC",
            "IOReportGroupName": groupName,
            "IOReportSubGroupName": "Energy Counters",
            "IOReportChannelInfo": ["IOReportChannelUnit": NSNumber(value: unit)],
            "LegendChannel": legend,
        ])
    }

    /// The AppleCLPC drivers running on this Mac: registry entry ID and bundle ID.
    static func liveDrivers() -> [(id: UInt64, bundle: String)] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleCLPC"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var drivers: [(id: UInt64, bundle: String)] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS,
                  let bundle = IORegistryEntryCreateCFProperty(entry, "CFBundleIdentifier" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String else { continue }
            drivers.append((id: id, bundle: bundle))
        }
        return drivers
    }
}
