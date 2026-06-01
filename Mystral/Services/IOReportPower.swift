import Foundation

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

    private let copyChannels: CopyChannels
    private let createSub: CreateSub
    private let createSamples: CreateSamples
    private let createDelta: CreateDelta
    private let iterate: IterateFn
    private let chanName: ChanStr
    private let getUnit: ChanStr
    private let simpleInt: SimpleInt

    private let subscription: AnyObject
    private let channels: CFMutableDictionary
    private var previous: CFDictionary?
    private var previousUptime: TimeInterval = 0

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

        guard let chans = cc("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
              let mut = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, chans) else { return nil }
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = cs(nil, mut, &subbed, 0, nil)?.takeRetainedValue() else { return nil }
        channels = mut
        subscription = sub
    }

    /// Returns (cpu, gpu) watts. Components are nil when unavailable (e.g. the
    /// first call, before there is a previous sample to diff against).
    func sample() -> (cpu: Double?, gpu: Double?) {
        guard let current = createSamples(subscription, channels, nil)?.takeRetainedValue() else {
            return (nil, nil)
        }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previous = current; previousUptime = now }
        guard let prev = previous else { return (nil, nil) }
        let elapsed = now - previousUptime
        guard elapsed > 0,
              let delta = createDelta(prev, current, nil)?.takeRetainedValue() else { return (nil, nil) }

        var cpuJoules = 0.0, gpuJoules = 0.0
        var sawCPU = false, sawGPU = false
        _ = iterate(delta) { [self] channel in
            let name = (chanName(channel)?.takeUnretainedValue()).map { $0 as String } ?? ""
            let unit = (getUnit(channel)?.takeUnretainedValue()).map { $0 as String } ?? ""
            let raw = simpleInt(channel, 0)
            if name == "CPU Energy" {
                cpuJoules += IOReportPower.energyToJoules(raw: raw, unit: unit); sawCPU = true
            } else if name == "GPU Energy" {
                gpuJoules += IOReportPower.energyToJoules(raw: raw, unit: unit); sawGPU = true
            }
            return 0
        }
        return (sawCPU ? cpuJoules / elapsed : nil, sawGPU ? gpuJoules / elapsed : nil)
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
