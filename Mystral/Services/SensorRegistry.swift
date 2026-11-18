import Foundation
import SwiftUI

enum SensorCategory: String, CaseIterable, Sendable {
    /// Every CPU cluster sensor: performance, efficiency and (M5 on) super cores.
    /// Which cluster a sensor belongs to is in its name; the clusters a chip has
    /// differ too much between generations for one category per cluster.
    case cpu = "CPU"
    case cpuSummary = "CPU Summary"
    case gpu = "GPU"
    case soc = "SoC"
    case memory = "Memory"
    case ssd = "SSD"
    case battery = "Battery"
    case airflow = "Airflow"
    case board = "Board"
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
    /// Keys whose meaning holds on every Apple Silicon Mac that has them.
    private static let exactKeys: [String: (String, SensorCategory)] = [
        // Summary values the SMC computes
        "TCMz": ("CPU Die Max", .cpuSummary),
        "TCMb": ("CPU Virtual Die", .cpuSummary),
        "TCDX": ("SoC Die Max", .cpuSummary),
        "TVD0": ("CPU Virtual Die", .soc),          // same value as TCMb
        "TCHP": ("CPU Heat Pipe", .other),

        "TB0T": ("Battery 1", .battery),
        "TB1T": ("Battery 2", .battery),
        "TB2T": ("Battery 3", .battery),

        "TaLP": ("Airflow Left", .airflow),
        "TaRP": ("Airflow Right", .airflow),
        "TaRF": ("Airflow Right", .airflow),
        "TaLT": ("Thunderbolt Left", .board),       // port proximity, not an intake
        "TaRT": ("Thunderbolt Right", .board),
        "TAOL": ("Ambient", .airflow),

        "TH0x": ("SSD NAND", .ssd),
        "TSDD": ("SSD Diode", .ssd),
        "TSCP": ("SoC Probe", .soc),
        "TMVR": ("Memory Regulator", .memory),
        "TVMN": ("Voltage Probe", .vrm),            // M5: a probe maximum, not virtual memory
        "TW0P": ("Wireless Module", .board),
        "TTSp": ("Touch Sensor", .board),
        "TUCp": ("USB-C Port", .board),
        "TR0Z": ("Calibration Constant", .other),   // fixed value, never a reading
    ]

    /// M1 publishes its efficiency-cluster readings among the `Tp` keys.
    /// From exelban/stats (MIT), Modules/Sensors/values.swift.
    private static let m1EfficiencyKeys: Set<String> = ["Tp09", "Tp0T"]

    /// Name and category of an SMC temperature key on a given chip.
    ///
    /// Apple documents none of these keys, and a key can mean different things on
    /// different chips. The rules group keys by prefix. They were checked against
    /// what exelban/stats, vladkens/macmon, metaspartan/mactop and dkorunic/iSMC do,
    /// against a CPU-only / E-core-only / GPU-only load test on an M3 Pro, and
    /// against the load captures iSMC publishes for M1 Ultra, M3, M3 Pro/Max, M4,
    /// M4 Pro/Max, M5, M5 Pro/Max and M6: a group is CPU, GPU or SoC only if it warms
    /// under that load, and storage, battery and board sensors only if it does not.
    ///
    /// No key is named after one core. Each cluster publishes groups of probes,
    /// aggregates and maxima, and none of those projects can tie a key to a core.
    static func classify(_ key: String, chip: HardwareInfo.Chip) -> (name: String, category: SensorCategory) {
        if let known = exactKeys[key] { return known }
        let characters = Array(key)
        guard characters.count == 4 else { return (key, .other) }
        let third = characters[2], last = characters[3]

        switch key.prefix(2) {
        // CPU clusters
        case "Tp":
            if third == "D" { return ("Power Delivery", .vrm) }        // M1: TpD0… never follow CPU load
            if third == "x" { return ("CPU Die Aggregate", .cpuSummary) }
            if chip.family == 1, m1EfficiencyKeys.contains(key) { return ("CPU E-Cluster", .cpu) }
            return (performanceClusterName(chip), .cpu)
        case "Te":
            // Tpx… and Tex… (M4) are per-die aggregates: half of them repeat the maximum
            // of a probe group exactly. They are summaries, not further probes.
            if third == "x" { return ("CPU Die Aggregate", .cpuSummary) }
            // M1 uses Te0x for the CPU die; from M2 on they are the efficiency cluster.
            return (chip.family == 1 ? "CPU Die" : "CPU E-Cluster", .cpu)
        case "Tc":
            return ("CPU", .cpu)                                       // M1
        case "Tm":
            // M5 Pro/Max reuse Tm for their performance cluster: 40 keys that warm by
            // 14–22 °C under CPU load, where memory sensors move by 1–3 °C.
            if chip.family == 5, chip.tier != .base { return ("CPU P-Cluster", .cpu) }
            return ("Memory", .memory)

        case "Tg": return ("GPU", .gpu)

        // SoC: warms with CPU or GPU load, but is neither cluster
        case "Tf": return ("SoC Fabric", .soc)
        case "Th": return ("SoC Heatsink", .soc)
        case "Td": return ("SoC Diode", .soc)                          // M1
        case "TE", "TF": return ("SoC", .soc)
        case "TQ": return ("Image Signal Processor", .soc)             // A18 Pro
        case "TN": return ("SoC Package", .soc)
        case "Ts":
            // Ts…P never moves under load (SSD controller); every other Ts key
            // follows CPU and GPU load on every chip from M1 to M6.
            return last == "P" ? ("SSD Controller", .ssd) : ("SoC", .soc)
        case "TU":
            if third == "D" { return ("SoC Uncore", .soc) }            // M4 Pro, M5 Pro/Max: follows GPU load
            if third == "V" { return ("SoC Regulator", .vrm) }
            return (key, .other)
        case "TC":
            // M1: TC1x…TCAx are groups of die probes.
            if chip.family == 1, (third.isNumber && third != "0") || third == "A" { return ("SoC Die Probe", .soc) }
            return (key, .other)

        // Storage
        case "TH": return ("SSD", .ssd)
        case "TS":
            if last == "P" || last == "p" { return ("SSD Proximity", .ssd) }
            if third == "V" || third == "W" || third == "X" { return ("SoC Regulator", .vrm) }
            if third == "C" { return ("System Controller", .board) }
            return (key, .other)

        // Battery
        case "TB":
            return last == "T" || last == "S" ? ("Battery", .battery) : (key, .other)
        case "TG":
            // Uppercase G is the battery gas gauge on Apple Silicon, not the GPU.
            return "ABCHV".contains(last) ? ("Battery Gauge", .battery) : (key, .other)

        // Air and enclosure
        case "Ta":
            // M5 and M6 add Ta0x keys that warm with the CPU; they are not airflow.
            if third.isNumber, last != "p" { return ("SoC", .soc) }
            return ("Airflow", .airflow)
        case "TA": return ("Ambient", .airflow)
        case "TD": return ("Board Diode", .board)                      // no response to any load
        case "TT": return ("Thunderbolt", .board)
        case "TI": return ("I/O", .board)
        case "TL": return ("Display", .board)
        case "TW": return ("Wireless Module", .board)
        case "TM": return ("Memory", .memory)

        // Power
        case "Tr": return ("Power Delivery", .vrm)                     // M1
        case "TP":
            switch third {
            case "D": return ("Power Delivery", .vrm)
            case "M": return ("Power Management", .vrm)
            case "S": return ("Power Supply", .vrm)
            case "H": return ("Power Heatsink", .vrm)
            case "V": return ("Power Probe", .vrm)
            default: return (key, .other)
            }
        case "TR":
            return third == "D" ? ("Power Delivery", .vrm) : ("Radio", .board)
        case "TV":
            // Mostly values the SMC models rather than measures.
            switch third {
            case "D": return ("Virtual Die", .soc)
            case "A": return ("Virtual Ambient", .airflow)
            case "M", "m", "h": return ("Virtual Memory", .memory)
            case "V": return ("Virtual Voltage", .vrm)
            case "N": return ("Voltage Probe", .vrm)
            default: return third.isNumber ? ("Voltage Probe", .vrm) : ("Virtual Sensor", .other)
            }

        default:
            return (key, .other)
        }
    }

    /// What the `Tp` keys measure depends on the cores the chip has.
    private static func performanceClusterName(_ chip: HardwareInfo.Chip) -> String {
        guard chip.hasSuperCores else { return "CPU P-Cluster" }
        // M5 Pro/Max and M6 have both super and performance cores behind Tp keys.
        return chip.hasPerformanceCores ? "CPU Super/P-Cluster" : "CPU Super-Cluster"
    }

    /// True when a rule or the exact-key table knows this key.
    static func isRecognized(_ key: String) -> Bool {
        classify(key, chip: HardwareInfo.chip).name != key
    }

    static func nameForKey(_ key: String) -> String {
        classify(key, chip: HardwareInfo.chip).name
    }

    static func categoryForKey(_ key: String) -> SensorCategory {
        classify(key, chip: HardwareInfo.chip).category
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

    /// CPU-cluster sensors that carry a live reading. Like macmon and mactop, the
    /// CPU average covers every cluster the chip has.
    static func cpuCoreSensors(from sensors: [Sensor]) -> [Sensor] {
        sensors.filter { categoryForKey($0.id) == .cpu && $0.temperature != parkedCpuReading }
    }

    static func gpuCoreSensors(from sensors: [Sensor]) -> [Sensor] {
        sensors.filter { categoryForKey($0.id) == .gpu }
    }

    /// The three whole-CPU values every chip publishes, in display order. Other
    /// summary keys (the per-die aggregates on M4) stay in the Sensors list.
    static let headlineSummaryKeys = ["TCMz", "TCMb", "TCDX"]

    static func cpuSummarySensors(from sensors: [Sensor]) -> [Sensor] {
        headlineSummaryKeys.compactMap { key in sensors.first { $0.id == key } }
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

    /// What a fan curve follows when its profile names no sensor: the hottest point
    /// of the CPU, which is the highest of TCMz and the CPU cluster sensors.
    ///
    /// TCMz is the SMC's own die maximum (M1–M4), and where it is published it equals
    /// the hottest cluster sensor. M5 and M6 do not publish it. Never the average: the
    /// same curve would react far later.
    ///
    /// TCMz alone is not steady on M4 Pro/Max. It is the maximum over the keys that are
    /// live that instant, so when the performance cores switch off for a second it
    /// falls by 15–20 °C and comes straight back, and it lags for a tick when the two
    /// key banks swap. The cluster sensors, live or held through such a gap, do not.
    static func defaultDrivingTemperature(from sensors: [Sensor]) -> Double {
        let dieMax = sensors.first(where: { $0.id == defaultCpuSensorKey })?.temperature ?? 0
        let hottest = max(dieMax, cpuMaximumTemperature(from: sensors))
        return hottest > 0 ? hottest : (sensors.first?.temperature ?? 0)
    }
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

    /// - Parameter trace: the lines of `SensorTrace.report`, appended as they are.
    static func exportDiagnosticData(sensors: [Sensor], fans: [Fan], trace: [String] = []) -> String {
        var lines: [String] = []
        lines.append("=== Mystral SMC Export ===")
        lines.append("Date: \(ISO8601DateFormatter().string(from: Date()))")
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        lines.append("Mystral: \(version) (\(build))")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Model: \(HardwareInfo.modelIdentifier())")
        lines.append("Chip: \(HardwareInfo.chipName()) (family \(HardwareInfo.chip.family.map(String.init) ?? "unknown"))")

        let chip = detectChip(sensors: sensors, fans: fans)
        let levels = chip.cores.levels.map { "\($0.name) \($0.cores)" }.joined(separator: ", ")
        lines.append("Detected chip: \(chip.chipName)")
        lines.append("CPU cores: \(chip.cores.total) (\(levels)), GPU cores: \(chip.cores.gpu)")
        lines.append("CPU sensors: \(chip.cpuSensorCount), GPU sensors: \(chip.gpuSensorCount)")
        lines.append("Supported: \(chip.isSupported)")
        lines.append("")

        lines.append("=== All Sensors (\(sensors.count)) ===")
        for sensor in sensors {
            let cat = categoryForKey(sensor.id)
            let known = isRecognized(sensor.id) ? "KNOWN" : "UNMAPPED"
            let held = sensor.isHeld ? " | HELD" : ""
            lines.append("\(sensor.id) | \(sensor.name) | \(cat.rawValue) | \(String(format: "%.2f", sensor.temperature))°C | \(known)\(held)")
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

        if !trace.isEmpty {
            lines.append("")
            lines.append(contentsOf: trace)
        }

        lines.append("")
        lines.append("=== Instructions ===")
        lines.append("Send this file to the developer to add support for your chip.")
        lines.append("Keys marked [NEEDS MAPPING] need human-readable names.")

        return lines.joined(separator: "\n")
    }
}

/// Keeps per-sensor temperature history across ticks, and bridges the moments when
/// the SMC switches CPU keys off.
///
/// A sensor can be missing for a tick or two: its read failed, or the value was
/// outside `SensorRegistry.plausibleTemperatureRange` and was dropped. Its history
/// used to be thrown away then, so the sensor started again from a single sample.
/// Here a short absence repeats the last value for each missed tick, so the history
/// keeps one entry per tick and stays lined up in time with the other sensors.
/// A long absence discards it.
///
/// CPU cluster keys go further. An M4 Pro publishes two banks of 51 performance
/// keys. Under heavy load both are live; under light load only one is, and they take
/// turns; when the cores idle, both are off for a second or two. A bank that is off
/// reads exactly 40.0 °C or a few degrees around zero. So the CPU went from 61
/// sensors to 10 and back between ticks, and the average, the maximum and the grid
/// jumped with it (issue #8; the same shows in iSMC's M4 Pro recording).
///
/// A key that just went off is therefore held at its last live reading for a few
/// ticks, but only to fill a gap: as many keys are shown as were live at once during
/// the hold window, never more. When the other bank takes over, as many keys are
/// live as before and nothing is held.
///
/// The count to fill up to must come from live keys only. It used to be the number
/// shown on the previous tick, held keys included. On an M4 Pro the banks take turns
/// every 2–6 s, faster than a hold expires, so after both had been live once the
/// bank that was off was held again and again and the count stayed at both banks for
/// good (96 instead of 51 for ten minutes in the trace attached to issue #8).
struct SensorHistoryStore {
    /// Ticks a sensor may be missing before its history is discarded.
    static let maximumMissedTicks = 5
    /// How long a CPU key that went off keeps showing its last live reading.
    static let cpuHoldDuration: TimeInterval = 10

    /// Hold ticks for a polling interval: about `cpuHoldDuration`, at least one tick.
    static func cpuHoldTicks(forPollingInterval interval: TimeInterval) -> Int {
        max(1, Int((cpuHoldDuration / max(0.1, interval)).rounded()))
    }

    private var histories: [String: [Double]] = [:]
    private var missedTicks: [String: Int] = [:]
    private var lastLiveCPU: [String: (value: Double, missed: Int)] = [:]
    /// How many CPU cluster keys were live on each of the last hold-window ticks,
    /// oldest first, this tick excluded.
    private var recentLiveCPUCounts: [Int] = []

    /// Attach the stored history to each sensor and record its current temperature.
    /// CPU cluster keys that are parked or absent are held at their last live reading
    /// (`Sensor.isHeld`); absent ones are added back to `sensors`.
    mutating func carry(into sensors: inout [Sensor], maxHistory: Int,
                        cpuHoldTicks: Int = SensorHistoryStore.maximumMissedTicks,
                        isCPUCluster: (String) -> Bool = { SensorRegistry.categoryForKey($0) == .cpu }) {
        holdGatedCPUKeys(in: &sensors, holdTicks: max(1, cpuHoldTicks), isCPUCluster: isCPUCluster)

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

    private mutating func holdGatedCPUKeys(in sensors: inout [Sensor], holdTicks: Int, isCPUCluster: (String) -> Bool) {
        var liveIDs = Set<String>()
        var parkedIndex: [String: Int] = [:]
        for i in sensors.indices where isCPUCluster(sensors[i].id) {
            if sensors[i].temperature == SensorRegistry.parkedCpuReading {
                parkedIndex[sensors[i].id] = i
            } else {
                liveIDs.insert(sensors[i].id)
                lastLiveCPU[sensors[i].id] = (sensors[i].temperature, 0)
            }
        }
        for (id, entry) in lastLiveCPU where !liveIDs.contains(id) {
            lastLiveCPU[id] = entry.missed >= holdTicks ? nil : (entry.value, entry.missed + 1)
        }

        // Fill up to the most keys that were live at once during the hold window, most
        // recently live first, so a key that just went off wins over a bank that has
        // been idle for a while.
        let gap = (recentLiveCPUCounts.suffix(holdTicks).max() ?? 0) - liveIDs.count
        recentLiveCPUCounts.append(liveIDs.count)
        if recentLiveCPUCounts.count > holdTicks {
            recentLiveCPUCounts.removeFirst(recentLiveCPUCounts.count - holdTicks)
        }
        let held = gap > 0
            ? Array(lastLiveCPU.filter { !liveIDs.contains($0.key) }
                .sorted { ($0.value.missed, $0.key) < ($1.value.missed, $1.key) }
                .prefix(gap))
            : []
        guard !held.isEmpty else { return }
        var appended = false
        for (id, entry) in held {
            if let index = parkedIndex[id] {
                sensors[index].temperature = entry.value
                sensors[index].isHeld = true
            } else {
                sensors.append(Sensor(id: id, name: SensorRegistry.nameForKey(id), temperature: entry.value, isHeld: true))
                appended = true
            }
        }
        // The helper lists keys in SMC order, which is sorted; keep a held key in its place.
        if appended { sensors.sort { $0.id < $1.id } }
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
