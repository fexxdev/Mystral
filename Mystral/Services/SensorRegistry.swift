import Foundation
import SwiftUI

enum SensorCategory: String, CaseIterable, Sendable {
    case cpuPerformance = "CPU P-Cores"
    case cpuEfficiency = "CPU E-Cores"
    case cpuSummary = "CPU Summary"
    case gpu = "GPU"
    case soc = "SoC"
    case memory = "Memory"
    case ssd = "SSD"
    case battery = "Battery"
    case airflow = "Airflow"
    case vrm = "VRM"
    case other = "Other"

    var localizedName: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

struct SensorInfo: Sendable {
    let key: String
    let name: String
    let category: SensorCategory
}

enum SensorRegistry {
    /// The chip family of this Mac (1 for M1 … 5 for M5), nil if unknown.
    static let chipFamily: Int? = HardwareInfo.chipFamily

    /// Keys whose meaning holds on every Apple Silicon Mac that has them.
    private static let exactKeys: [String: (String, SensorCategory)] = [
        // CPU summary values computed by the SMC
        "TCMz": ("CPU Die Max", .cpuSummary),
        "TCMb": ("CPU Virtual Die", .cpuSummary),
        "TCDX": ("SoC Die Max", .cpuSummary),
        "TVD0": ("CPU Virtual Die", .other),      // same value as TCMb; not a regulator
        "TCHP": ("CPU Heat Pipe", .other),

        // Battery
        "TB0T": ("Battery 1", .battery),
        "TB1T": ("Battery 2", .battery),
        "TB2T": ("Battery 3", .battery),

        // Airflow and enclosure
        "TaLP": ("Airflow Left", .airflow),
        "TaRP": ("Airflow Right", .airflow),
        "TaRF": ("Airflow Right", .airflow),
        "TaLT": ("Thunderbolt Left", .airflow),   // port proximity, not an intake
        "TaRT": ("Thunderbolt Right", .airflow),
        "TAOL": ("Ambient", .airflow),

        // Memory, storage, radios
        "TMVR": ("Memory Regulator", .memory),
        "TW0P": ("Wireless Module", .other),
        "TSCP": ("SoC Probe", .soc),
    ]

    /// M1 publishes its efficiency-cluster readings among the `Tp` keys.
    /// From exelban/stats (MIT), Modules/Sensors/values.swift.
    private static let m1EfficiencyKeys: Set<String> = ["Tp09", "Tp0T"]

    /// Name and category of an SMC temperature key.
    ///
    /// Apple documents none of these keys, and a key can mean different things on
    /// different chips. Keys are grouped by prefix, checked with CPU-only, E-core-only
    /// and GPU-only load tests on an M3 Pro and against what open-source monitors do
    /// (exelban/stats, vladkens/macmon, metaspartan/mactop, dkorunic/iSMC). No key is
    /// named after a specific core: each cluster publishes groups of probes,
    /// aggregates and maxima, and none of those projects can tie a key to one core.
    static func classify(_ key: String, chipFamily: Int?) -> (name: String, category: SensorCategory) {
        if let known = exactKeys[key] { return known }
        switch key.prefix(2) {
        case "Tp":
            if chipFamily == 1, m1EfficiencyKeys.contains(key) { return ("CPU E-Cluster", .cpuEfficiency) }
            return ("CPU P-Cluster", .cpuPerformance)
        case "Te":
            // M1 uses Te0x for the CPU die; from M2 on they are efficiency-cluster groups.
            if chipFamily == 1 { return ("CPU Die", .cpuSummary) }
            return ("CPU E-Cluster", .cpuEfficiency)
        case "Tg": return ("GPU", .gpu)
        case "TG": return ("Battery Gauge", .battery)          // uppercase G: gas gauge, not GPU
        case "Tf": return ("SoC Fabric", .soc)                 // per-SKU blocks near CPU or GPU, plus held min/max
        case "Tm": return ("Memory", .memory)
        case "Ts": return key.hasSuffix("P") ? ("SSD Controller", .ssd) : ("SoC", .soc)
        case "TS": return key.hasSuffix("P") ? ("SSD Proximity", .ssd) : (key, .other)
        case "TH": return ("SSD NAND", .ssd)
        case "Th": return ("Heatsink", .other)
        case "TB": return ("Battery", .battery)
        case "Ta", "TA": return ("Airflow", .airflow)
        case "TV": return ("Voltage Regulator", .vrm)
        case "TD": return ("SoC Diode", .soc)
        case "TE", "TF": return ("SoC", .soc)
        default:
            if key.hasPrefix("TPD") || key.hasPrefix("TRD") { return ("Power Delivery", .vrm) }
            return (key, .other)
        }
    }

    /// True when a rule or the exact-key table knows this key.
    static func isRecognized(_ key: String) -> Bool {
        classify(key, chipFamily: chipFamily).name != key
    }

    static func nameForKey(_ key: String) -> String {
        classify(key, chipFamily: chipFamily).name
    }

    static func categoryForKey(_ key: String) -> SensorCategory {
        classify(key, chipFamily: chipFamily).category
    }

    static func info(for key: String) -> SensorInfo {
        SensorInfo(key: key, name: nameForKey(key), category: categoryForKey(key))
    }

    static func groupByCategory(_ sensors: [Sensor]) -> [(SensorCategory, [Sensor])] {
        var grouped: [SensorCategory: [Sensor]] = [:]
        for sensor in sensors {
            let cat = categoryForKey(sensor.id)
            grouped[cat, default: []].append(sensor)
        }
        return SensorCategory.allCases.compactMap { cat in
            guard let sensors = grouped[cat], !sensors.isEmpty else { return nil }
            return (cat, sensors)
        }
    }

    /// A CPU key reading exactly 40.0 °C is a parked slot: on M4 Pro/Max the SMC
    /// alternates between two banks of P-cluster keys and holds the idle one at 40.0.
    static let parkedCpuReading = 40.0

    /// CPU-cluster sensors (performance and efficiency) that carry a live reading.
    /// Like macmon and mactop, the CPU average covers both clusters.
    static func cpuCoreSensors(from sensors: [Sensor]) -> [Sensor] {
        sensors.filter { sensor in
            let category = categoryForKey(sensor.id)
            return (category == .cpuPerformance || category == .cpuEfficiency)
                && sensor.temperature != parkedCpuReading
        }
    }

    static func gpuCoreSensors(from sensors: [Sensor]) -> [Sensor] {
        sensors.filter { categoryForKey($0.id) == .gpu }
    }

    static func cpuSummarySensors(from sensors: [Sensor]) -> [Sensor] {
        sensors.filter { categoryForKey($0.id) == .cpuSummary }
    }

    static func cpuMaximumTemperature(from sensors: [Sensor]) -> Double {
        if let maximumCore = cpuCoreSensors(from: sensors).map(\.temperature).max() {
            return maximumCore
        }
        return ["TCMz", "TCMb"].compactMap { key in
            sensors.first(where: { $0.id == key })?.temperature
        }.max() ?? 0
    }

    static let defaultCpuSensorKey = "TCMz"
    static let defaultGpuSensorKey = ""

    /// Readings outside this range are not real temperatures. Some SMC keys are
    /// unpopulated rails that read 1–3 °C, and a bad read can return a tiny value
    /// for every key at once; both pulled the CPU average and maximum toward 0 °C
    /// on the dashboard (seen alongside issue #4). A running Mac's sensors do not
    /// read below 10 °C, and nothing in it survives 130 °C.
    static let plausibleTemperatureRange: ClosedRange<Double> = 10...130

    static func isPlausibleTemperature(_ value: Double) -> Bool {
        value.isFinite && plausibleTemperatureRange.contains(value)
    }

    struct ChipDetection: Sendable {
        let chipName: String
        let isSupported: Bool
        /// Physical cores, from the system (0 when unknown).
        let cores: HardwareInfo.CoreCounts
        /// SMC temperature keys Mystral reads for the CPU and GPU; not core counts.
        let cpuSensorCount: Int
        let gpuSensorCount: Int
        let hasFanControl: Bool
    }

    static func detectChip(sensors: [Sensor], fans: [Fan],
                           cores: HardwareInfo.CoreCounts = HardwareInfo.coreCounts) -> ChipDetection {
        let keys = Set(sensors.map(\.id))
        let cpuCores = cpuCoreSensors(from: sensors).count
        let gpuCores = gpuCoreSensors(from: sensors).count
        let hasSummary = keys.contains("TCMz") || keys.contains("TCMb")
        // Mystral forces every fan it drives, so a fan still in automatic mode means the
        // SMC did not accept manual control (or the helper hasn't applied it yet).
        let hasFanControl = fans.contains { $0.maxRPM > $0.minRPM && $0.mode == .forced }

        let sysName = HardwareInfo.chipName()
        let chipName = sysName.isEmpty ? (cpuCores > 0 ? "Apple Silicon" : "Unknown") : sysName

        return ChipDetection(
            chipName: chipName,
            isSupported: hasSummary && cpuCores > 0,
            cores: cores,
            cpuSensorCount: cpuCores,
            gpuSensorCount: gpuCores,
            hasFanControl: hasFanControl
        )
    }

    static func exportDiagnosticData(sensors: [Sensor], fans: [Fan]) -> String {
        var lines: [String] = []
        lines.append("=== Mystral SMC Export ===")
        lines.append("Date: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Model: \(HardwareInfo.modelIdentifier())")
        lines.append("Chip: \(HardwareInfo.chipName()) (family \(chipFamily.map(String.init) ?? "unknown"))")

        let chip = detectChip(sensors: sensors, fans: fans)
        lines.append("Detected chip: \(chip.chipName)")
        lines.append("CPU cores: \(chip.cores.total) (P \(chip.cores.performance), E \(chip.cores.efficiency)), GPU cores: \(chip.cores.gpu)")
        lines.append("CPU sensors: \(chip.cpuSensorCount), GPU sensors: \(chip.gpuSensorCount)")
        lines.append("Supported: \(chip.isSupported)")
        lines.append("")

        lines.append("=== All Sensors (\(sensors.count)) ===")
        for sensor in sensors {
            let cat = categoryForKey(sensor.id)
            let known = isRecognized(sensor.id) ? "KNOWN" : "UNMAPPED"
            lines.append("\(sensor.id) | \(sensor.name) | \(cat.rawValue) | \(String(format: "%.2f", sensor.temperature))°C | \(known)")
        }

        lines.append("")
        lines.append("=== Fans (\(fans.count)) ===")
        for fan in fans {
            lines.append("Fan \(fan.id): \(fan.name) | RPM=\(fan.currentRPM) | target=\(fan.targetRPM) | min=\(fan.minRPM) | max=\(fan.maxRPM) | mode=\(fan.mode.rawValue)")
        }

        lines.append("")
        lines.append("=== Sensor Categories ===")
        let grouped = groupByCategory(sensors)
        for (cat, catSensors) in grouped {
            lines.append("\(cat.rawValue): \(catSensors.count) sensors")
            for s in catSensors {
                let known = isRecognized(s.id)
                lines.append("  \(s.id) → \(s.name) \(known ? "" : "[NEEDS MAPPING]")")
            }
        }

        lines.append("")
        lines.append("=== Instructions ===")
        lines.append("Send this file to the developer to add support for your chip.")
        lines.append("Keys marked [NEEDS MAPPING] need human-readable names.")

        return lines.joined(separator: "\n")
    }
}

/// Keeps per-sensor temperature history across ticks.
///
/// A sensor can be missing for a tick or two: its read failed, or the value was
/// outside `SensorRegistry.plausibleTemperatureRange` and was dropped. Its history
/// used to be thrown away then, so the sensor started again from a single sample.
/// Here a short absence repeats the last value for each missed tick, so the history
/// keeps one entry per tick and stays lined up in time with the other sensors.
/// A long absence discards it.
struct SensorHistoryStore {
    /// Ticks a sensor may be missing before its history is discarded.
    static let maximumMissedTicks = 5

    private var histories: [String: [Double]] = [:]
    private var missedTicks: [String: Int] = [:]

    /// Attach the stored history to each sensor and record its current temperature.
    mutating func carry(into sensors: inout [Sensor], maxHistory: Int) {
        let limit = max(1, maxHistory)
        var seen = Set<String>()
        for i in sensors.indices {
            let id = sensors[i].id
            seen.insert(id)
            sensors[i].history = histories[id] ?? []
            sensors[i].recordTemperature(sensors[i].temperature, maxHistory: limit)
            histories[id] = sensors[i].history
            missedTicks[id] = nil
        }
        for id in histories.keys where !seen.contains(id) {
            let missed = (missedTicks[id] ?? 0) + 1
            if missed > Self.maximumMissedTicks {
                histories[id] = nil
                missedTicks[id] = nil
            } else {
                missedTicks[id] = missed
                if var history = histories[id], let last = history.last {
                    history.append(last)
                    if history.count > limit { history.removeFirst(history.count - limit) }
                    histories[id] = history
                }
            }
        }
    }
}

extension SensorRegistry {
    /// Combine several sensors' histories into one series, aligned on the newest
    /// sample. Histories have different lengths (a sensor that appeared later, or
    /// was dropped for a while), so position `i` from the start does not mean the
    /// same moment for every sensor; position `i` from the end does.
    static func alignedHistory(of sensors: [Sensor], combine: ([Double]) -> Double) -> [Double] {
        let length = sensors.map(\.history.count).max() ?? 0
        guard length > 0 else { return [] }
        var series: [Double] = []
        series.reserveCapacity(length)
        for i in 0..<length {
            let fromEnd = length - 1 - i
            let values = sensors.compactMap { sensor -> Double? in
                let h = sensor.history
                return h.count > fromEnd ? h[h.count - 1 - fromEnd] : nil
            }
            guard !values.isEmpty else { continue }
            series.append(combine(values))
        }
        return series
    }
}
