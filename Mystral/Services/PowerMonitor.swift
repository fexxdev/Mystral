import Foundation

/// Reads instantaneous power: total system power from SMC `PSTR`, and CPU/GPU
/// power from IOReport. All reads are user-level (no root). Sampled once per
/// menu-bar timer tick by `MenuBarManager`.
@Observable
@MainActor
final class PowerMonitor {
    private(set) var totalWatts: Double?
    private(set) var cpuWatts: Double?
    private(set) var gpuWatts: Double?

    /// Rolling watt history for the dashboard chart — one sample per FanController
    /// tick, so it shares the exact polling cadence as sensor history. At the default
    /// 2 s interval, `maxHistory` samples ≈ the last 5 minutes.
    private(set) var totalHistory: [Double] = []
    private(set) var cpuHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []
    static let maxHistory = 150

    private let smc: SMCKit?
    private let ioreport: IOReportPower?

    init() {
        let kit = SMCKit()
        var opened: SMCKit?
        do { try kit.open(); opened = kit } catch { opened = nil }
        smc = opened
        ioreport = IOReportPower()
    }

    func sample() {
        if let smc, let watts = try? smc.readFloat(key: "PSTR"), watts > 0 {
            totalWatts = watts
        } else {
            totalWatts = nil
        }
        if let reading = ioreport?.sample() {
            cpuWatts = reading.cpu
            gpuWatts = reading.gpu
        } else {
            cpuWatts = nil
            gpuWatts = nil
        }
        if let t = totalWatts { totalHistory = Self.appendCapped(t, to: totalHistory, maxHistory: Self.maxHistory) }
        if let c = cpuWatts { cpuHistory = Self.appendCapped(c, to: cpuHistory, maxHistory: Self.maxHistory) }
        if let g = gpuWatts { gpuHistory = Self.appendCapped(g, to: gpuHistory, maxHistory: Self.maxHistory) }
    }

    /// Append a value to a rolling history, trimming the oldest samples beyond `maxHistory`.
    nonisolated static func appendCapped(_ value: Double, to history: [Double], maxHistory: Int) -> [Double] {
        var h = history
        h.append(value)
        if h.count > maxHistory { h.removeFirst(h.count - maxHistory) }
        return h
    }
}
