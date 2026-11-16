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

    /// Upper bound for the SMC `PSTR` system total. Even a Mac Pro's power supply
    /// stays under this; anything above it is a bad read, not real power.
    nonisolated static let maximumPlausibleTotalWatts: Double = 1500

    /// `minimumInterval` is the shortest window IOReport may average over. Pass
    /// about half the polling interval so two timer ticks that fire close together
    /// cannot turn a normal energy delta into a huge wattage.
    func sample(maxHistory: Int = PowerMonitor.maxHistory, minimumInterval: TimeInterval = 1) {
        let historyLimit = max(1, maxHistory)
        if let smc, let watts = try? smc.readFloat(key: "PSTR"), Self.isPlausibleTotal(watts) {
            totalWatts = watts
        } else {
            totalWatts = nil
        }
        if let reading = ioreport?.sample(minimumInterval: minimumInterval, systemWatts: totalWatts) {
            cpuWatts = reading.cpu
            gpuWatts = reading.gpu
        } else {
            cpuWatts = nil
            gpuWatts = nil
        }
        if let t = totalWatts { totalHistory = Self.appendCapped(t, to: totalHistory, maxHistory: historyLimit) }
        if let c = cpuWatts { cpuHistory = Self.appendCapped(c, to: cpuHistory, maxHistory: historyLimit) }
        if let g = gpuWatts { gpuHistory = Self.appendCapped(g, to: gpuHistory, maxHistory: historyLimit) }
    }

    /// Drop the IOReport baseline, e.g. after wake, so the first reading after
    /// sleep is not averaged across the time the Mac was asleep.
    func resetBaseline() {
        ioreport?.reset()
    }

    nonisolated static func isPlausibleTotal(_ watts: Double) -> Bool {
        watts.isFinite && watts > 0 && watts <= maximumPlausibleTotalWatts
    }

    /// Watts as shown in the UI: one decimal below 10 W, whole watts above.
    /// An idle Apple Silicon GPU draws tens of milliwatts and the CPU often 1–2 W,
    /// so rounding to whole watts showed real readings as "0 W" or "1 W".
    nonisolated static func formatWatts(_ watts: Double, locale: Locale = .current) -> String {
        let tenths = (watts * 10).rounded() / 10
        let digits = tenths < 10 ? 1 : 0
        return watts.formatted(.number.precision(.fractionLength(digits)).locale(locale)) + " W"
    }

    /// Append a value to a rolling history, trimming the oldest samples beyond `maxHistory`.
    nonisolated static func appendCapped(_ value: Double, to history: [Double], maxHistory: Int) -> [Double] {
        var h = history
        h.append(value)
        if h.count > maxHistory { h.removeFirst(h.count - maxHistory) }
        return h
    }
}
