import Foundation

/// What the CPU cluster keys did over the last ticks, one line per tick, for the
/// diagnostics export.
///
/// It exists to check, on Macs we do not own, how CPU keys switch off and on (see
/// `SensorHistoryStore`) and what the fan curve was given meanwhile. Each line carries
/// enough to recompute what other hold rules would have done with the same readings:
/// the live maximum (no hold), the held maximum (hold everything) and the input the
/// curve actually got. Nothing is written to disk until the user exports.
struct SensorTrace {
    struct Entry: Equatable {
        var time: Date
        /// CPU cluster keys the helper delivered with a live reading.
        var live: Int
        /// CPU cluster keys the helper delivered at the parked reading (40.0 °C).
        var parked: Int
        /// CPU cluster keys shown at their last live reading instead of this tick's.
        var held: Int
        /// Held keys that still count as current (`Sensor.isStale` is false).
        var heldCurrent: Int
        var firstLiveKey: String?
        var lastLiveKey: String?
        /// The hottest live CPU cluster key.
        var hottestLiveKey: String?
        var liveMaximum: Double?
        /// Live maxima of the `Tp…` and `Te…` keys, to see one cluster while the other is hotter.
        var performanceMaximum: Double?
        var efficiencyMaximum: Double?
        /// TCMz as the SMC reported it.
        var dieMaximum: Double?
        /// The hottest held reading, stale ones included: what holding everything would use.
        var heldMaximum: Double?
        /// The CPU maximum and average as the Dashboard shows them.
        var shownMaximum: Double
        var shownAverage: Double?
        /// The reading offered to the active profile's curve, and whether it was held.
        var driving: Double?
        var isDrivingHeld: Bool
        /// What the curve was given (after the pause and smoothing), if a curve ran.
        var curveInput: Double?
        /// The fan percentage last written for each fan.
        var targetPercent: [Double?]
        var fanRPM: [Int]
        var cpuWatts: Double?
        var gpuWatts: Double?
    }

    /// Thirty minutes at the default polling interval.
    static let capacity = 900

    private(set) var entries: [Entry] = []

    mutating func record(_ entry: Entry) {
        entries.append(entry)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    /// - Parameters:
    ///   - raw: the sensors as the helper delivered them, before holding.
    ///   - shown: the same tick after `SensorHistoryStore.carry`.
    static func entry(raw: [Sensor], shown: [Sensor], driving: SensorRegistry.DrivingReading?,
                      curveInput: Double?, fans: [Fan], targetPercent: [Double?] = [],
                      cpuWatts: Double? = nil, gpuWatts: Double? = nil, time: Date = Date(),
                      isCPUCluster: (String) -> Bool = { SensorRegistry.categoryForKey($0) == .cpu }) -> Entry {
        let cluster = raw.filter { isCPUCluster($0.id) }
        let live = cluster.filter { $0.temperature != SensorRegistry.parkedCpuReading }
        let liveKeys = live.map(\.id).sorted()
        let held = shown.filter(\.isHeld)
        func liveMaximum(prefix: String) -> Double? {
            live.filter { $0.id.hasPrefix(prefix) }.map(\.temperature).max()
        }
        return Entry(
            time: time,
            live: live.count,
            parked: cluster.count - live.count,
            held: held.count,
            heldCurrent: held.filter { !$0.isStale }.count,
            firstLiveKey: liveKeys.first,
            lastLiveKey: liveKeys.last,
            hottestLiveKey: live.max { ($0.temperature, $1.id) < ($1.temperature, $0.id) }?.id,
            liveMaximum: live.map(\.temperature).max(),
            performanceMaximum: liveMaximum(prefix: "Tp"),
            efficiencyMaximum: liveMaximum(prefix: "Te"),
            dieMaximum: raw.first { $0.id == SensorRegistry.defaultCpuSensorKey }?.temperature,
            heldMaximum: held.map(\.temperature).max(),
            shownMaximum: SensorRegistry.cpuMaximumTemperature(from: shown),
            shownAverage: SensorRegistry.cpuAverageTemperature(from: shown),
            driving: driving?.temperature,
            isDrivingHeld: driving?.isHeld ?? false,
            curveInput: curveInput,
            targetPercent: targetPercent,
            fanRPM: fans.map(\.currentRPM),
            cpuWatts: cpuWatts,
            gpuWatts: gpuWatts
        )
    }

    /// What the report says about the settings the trace was recorded under.
    struct Settings: Equatable {
        var pollingInterval: TimeInterval
        /// The active profile's sensor key; empty for the default.
        var curveSensor: String
        /// The active profile's curve for the first fan.
        var curve: [CurvePoint]
        var smoothingAlpha: Double?
        var minimumFanPercentage: Double
    }

    static let columns = [
        "time", "live", "parked", "held", "current", "live keys", "hottest", "TCMz", "Tp max", "Te max",
        "held max", "shown max", "shown avg", "driving", "paused", "curve", "target %", "fan RPM", "CPU W", "GPU W"
    ]

    /// The trace as lines for the export, oldest tick first.
    func report(_ settings: Settings) -> [String] {
        let holdTicks = SensorHistoryStore.cpuHoldTicks(forPollingInterval: settings.pollingInterval)
        let freshTicks = SensorHistoryStore.cpuFreshTicks(forPollingInterval: settings.pollingInterval)
        let sensor = settings.curveSensor.isEmpty ? "default (hottest CPU point)" : settings.curveSensor
        let curve = settings.curve.sorted { $0.temperature < $1.temperature }
            .map { "\(Self.number($0.temperature))°→\(Self.number($0.fanPercentage))%" }
            .joined(separator: " ")
        let smoothing = settings.smoothingAlpha.map { "on (alpha \(String(format: "%.2f", $0)))" } ?? "off"
        var lines = [
            "=== CPU Sensor Trace (\(entries.count) ticks, oldest first) ===",
            "Polling interval: \(Self.number(settings.pollingInterval)) s | hold: \(holdTicks) ticks"
                + " | current: \(freshTicks) ticks | curve sensor: \(sensor)",
            "Smoothing: \(smoothing) | minimum fan: \(Self.number(settings.minimumFanPercentage)) %"
                + " | curve: \(curve.isEmpty ? "-" : curve)",
            Self.columns.joined(separator: " | ")
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.S"
        for entry in entries {
            let keys = entry.firstLiveKey.map { "\($0)…\(entry.lastLiveKey ?? $0)" } ?? "-"
            lines.append([
                formatter.string(from: entry.time),
                String(entry.live),
                String(entry.parked),
                String(entry.held),
                String(entry.heldCurrent),
                keys,
                entry.hottestLiveKey ?? "-",
                Self.number(entry.dieMaximum),
                Self.number(entry.performanceMaximum),
                Self.number(entry.efficiencyMaximum),
                Self.number(entry.heldMaximum),
                Self.number(entry.shownMaximum),
                Self.number(entry.shownAverage),
                Self.number(entry.driving),
                entry.isDrivingHeld ? "yes" : "no",
                Self.number(entry.curveInput),
                entry.targetPercent.isEmpty ? "-" : entry.targetPercent.map(Self.number).joined(separator: "/"),
                entry.fanRPM.isEmpty ? "-" : entry.fanRPM.map(String.init).joined(separator: "/"),
                Self.number(entry.cpuWatts),
                Self.number(entry.gpuWatts)
            ].joined(separator: " | "))
        }
        return lines
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "-"
    }
}
