import Foundation

/// What the CPU cluster keys did over the last ticks, one line per tick, for the
/// diagnostics export.
///
/// It exists to check, on Macs we do not own, how CPU keys switch off and on (see
/// `SensorHistoryStore`) and what the fan curve was given meanwhile. Nothing is
/// written to disk until the user exports.
struct SensorTrace {
    struct Entry: Equatable {
        var time: Date
        /// CPU cluster keys the helper delivered with a live reading.
        var live: Int
        /// CPU cluster keys the helper delivered at the parked reading (40.0 °C).
        var parked: Int
        /// CPU cluster keys shown at their last live reading instead of this tick's.
        var held: Int
        var firstLiveKey: String?
        var lastLiveKey: String?
        var liveMaximum: Double?
        /// TCMz as the SMC reported it.
        var dieMaximum: Double?
        /// `SensorRegistry.defaultDrivingTemperature` after holding.
        var defaultDriving: Double
        /// What the active profile's curve was given (after smoothing), if a curve ran.
        var curveInput: Double?
        var fanRPM: [Int]
    }

    /// Ten minutes at the default polling interval.
    static let capacity = 300

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
    static func entry(raw: [Sensor], shown: [Sensor], curveInput: Double?, fans: [Fan],
                      time: Date = Date(),
                      isCPUCluster: (String) -> Bool = { SensorRegistry.categoryForKey($0) == .cpu }) -> Entry {
        let cluster = raw.filter { isCPUCluster($0.id) }
        let live = cluster.filter { $0.temperature != SensorRegistry.parkedCpuReading }
        let liveKeys = live.map(\.id).sorted()
        return Entry(
            time: time,
            live: live.count,
            parked: cluster.count - live.count,
            held: shown.filter(\.isHeld).count,
            firstLiveKey: liveKeys.first,
            lastLiveKey: liveKeys.last,
            liveMaximum: live.map(\.temperature).max(),
            dieMaximum: raw.first { $0.id == SensorRegistry.defaultCpuSensorKey }?.temperature,
            defaultDriving: SensorRegistry.defaultDrivingTemperature(from: shown),
            curveInput: curveInput,
            fanRPM: fans.map(\.currentRPM)
        )
    }

    /// The trace as lines for the export, oldest tick first.
    /// - Parameter curveSensor: the active profile's sensor key; empty for the default.
    func report(pollingInterval: TimeInterval, curveSensor: String) -> [String] {
        let holdTicks = SensorHistoryStore.cpuHoldTicks(forPollingInterval: pollingInterval)
        let sensor = curveSensor.isEmpty ? "default (hottest CPU point)" : curveSensor
        var lines = [
            "=== CPU Sensor Trace (\(entries.count) ticks, oldest first) ===",
            "Polling interval: \(Self.number(pollingInterval)) s | hold: \(holdTicks) ticks | curve sensor: \(sensor)",
            "time | live | parked | held | live keys | TCMz | live max | default | curve | fan RPM"
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
                keys,
                Self.number(entry.dieMaximum),
                Self.number(entry.liveMaximum),
                Self.number(entry.defaultDriving),
                Self.number(entry.curveInput),
                entry.fanRPM.isEmpty ? "-" : entry.fanRPM.map(String.init).joined(separator: "/")
            ].joined(separator: " | "))
        }
        return lines
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "-"
    }
}
