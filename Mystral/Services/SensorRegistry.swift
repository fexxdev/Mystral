import Foundation

enum SensorCategory: String, CaseIterable, Sendable {
    case cpuPerformance = "CPU P-Cores"
    case cpuEfficiency = "CPU E-Cores"
    case cpuSummary = "CPU Summary"
    case gpu = "GPU"
    case memory = "Memory"
    case ssd = "SSD"
    case battery = "Battery"
    case airflow = "Airflow"
    case vrm = "VRM"
    case other = "Other"
}

struct SensorInfo: Sendable {
    let key: String
    let name: String
    let category: SensorCategory
}

enum SensorRegistry {
    private static let catalog: [String: (String, SensorCategory)] = [
        // CPU Performance Cores (M1 through M5, keys vary by chip)
        "Tp01": ("CPU P-Core 1", .cpuPerformance),
        "Tp02": ("CPU P-Core 2", .cpuPerformance),
        "Tp03": ("CPU P-Core 3", .cpuPerformance),
        "Tp04": ("CPU P-Core 4", .cpuPerformance),
        "Tp05": ("CPU P-Core 5", .cpuPerformance),
        "Tp06": ("CPU P-Core 6", .cpuPerformance),
        "Tp07": ("CPU P-Core 7", .cpuPerformance),
        "Tp08": ("CPU P-Core 8", .cpuPerformance),
        "Tp0K": ("CPU P-Core 9", .cpuPerformance),
        "Tp0L": ("CPU P-Core 10", .cpuPerformance),
        "Tp0M": ("CPU P-Core 11", .cpuPerformance),
        "Tp0R": ("CPU P-Core 12", .cpuPerformance),
        "Tp0S": ("CPU P-Core 13", .cpuPerformance),
        "Tp0T": ("CPU P-Core 14", .cpuPerformance),
        "Tp0U": ("CPU P-Core 15", .cpuPerformance),
        "Tp0V": ("CPU P-Core 16", .cpuPerformance),
        "Tp0W": ("CPU P-Core 17", .cpuPerformance),
        "Tp0a": ("CPU P-Core 18", .cpuPerformance),
        "Tp0b": ("CPU P-Core 19", .cpuPerformance),
        "Tp0c": ("CPU P-Core 20", .cpuPerformance),
        "Tp0g": ("CPU P-Core 21", .cpuPerformance),
        "Tp0h": ("CPU P-Core 22", .cpuPerformance),
        "Tp0i": ("CPU P-Core 23", .cpuPerformance),
        "Tp0m": ("CPU P-Core 24", .cpuPerformance),
        "Tp0n": ("CPU P-Core 25", .cpuPerformance),
        "Tp0o": ("CPU P-Core 26", .cpuPerformance),
        "Tp0u": ("CPU P-Core 27", .cpuPerformance),
        "Tp0v": ("CPU P-Core 28", .cpuPerformance),
        "Tp0w": ("CPU P-Core 29", .cpuPerformance),
        "Tp0y": ("CPU P-Core 30", .cpuPerformance),
        "Tp0z": ("CPU P-Core 31", .cpuPerformance),
        "Tp10": ("CPU P-Core 32", .cpuPerformance),

        // CPU Efficiency Cores
        "Tp09": ("CPU E-Core 1", .cpuEfficiency),
        "Tp0A": ("CPU E-Core 2", .cpuEfficiency),
        "Tp0B": ("CPU E-Core 3", .cpuEfficiency),
        "Tp0C": ("CPU E-Core 4", .cpuEfficiency),
        "Tp0D": ("CPU E-Core 5", .cpuEfficiency),
        "Tp0E": ("CPU E-Core 6", .cpuEfficiency),
        "Tp16": ("CPU E-Core 7", .cpuEfficiency),
        "Tp17": ("CPU E-Core 8", .cpuEfficiency),
        "Tp18": ("CPU E-Core 9", .cpuEfficiency),
        "Tp1E": ("CPU E-Core 10", .cpuEfficiency),
        "Tp1F": ("CPU E-Core 11", .cpuEfficiency),
        "Tp1G": ("CPU E-Core 12", .cpuEfficiency),
        "Tp1I": ("CPU E-Core 13", .cpuEfficiency),
        "Tp1J": ("CPU E-Core 14", .cpuEfficiency),
        "Tp1K": ("CPU E-Core 15", .cpuEfficiency),
        "Tp1Q": ("CPU E-Core 16", .cpuEfficiency),
        "Tp1R": ("CPU E-Core 17", .cpuEfficiency),
        "Tp1S": ("CPU E-Core 18", .cpuEfficiency),
        "Tp3O": ("CPU E-Core 19", .cpuEfficiency),
        "Tp3P": ("CPU E-Core 20", .cpuEfficiency),
        "Tp3S": ("CPU E-Core 21", .cpuEfficiency),
        "Tp3T": ("CPU E-Core 22", .cpuEfficiency),
        "Tp3W": ("CPU E-Core 23", .cpuEfficiency),
        "Tp3X": ("CPU E-Core 24", .cpuEfficiency),

        // CPU Summary
        "TCMb": ("CPU Hotspot", .cpuSummary),
        "TCMz": ("CPU Max", .cpuSummary),
        "TCDX": ("CPU Die", .cpuSummary),
        "TCHP": ("CPU Package", .cpuSummary),

        // GPU Cores (vary by chip)
        "Tg00": ("GPU Core 1", .gpu),
        "Tg01": ("GPU Core 2", .gpu),
        "Tg04": ("GPU Core 3", .gpu),
        "Tg05": ("GPU Core 4", .gpu),
        "Tg08": ("GPU Core 5", .gpu),
        "Tg09": ("GPU Core 6", .gpu),
        "Tg0C": ("GPU Core 7", .gpu),
        "Tg0D": ("GPU Core 8", .gpu),
        "Tg0K": ("GPU Core 9", .gpu),
        "Tg0L": ("GPU Core 10", .gpu),
        "Tg0U": ("GPU Core 11", .gpu),
        "Tg0V": ("GPU Core 12", .gpu),
        "Tg0a": ("GPU Core 13", .gpu),
        "Tg0b": ("GPU Core 14", .gpu),
        "Tg0c": ("GPU Core 15", .gpu),
        "Tg0d": ("GPU Core 16", .gpu),
        "Tg0u": ("GPU Core 17", .gpu),
        "Tg0v": ("GPU Core 18", .gpu),
        "Tg12": ("GPU Core 19", .gpu),
        "Tg13": ("GPU Core 20", .gpu),
        "Tg1A": ("GPU Core 21", .gpu),
        "Tg1B": ("GPU Core 22", .gpu),
        "Tg1k": ("GPU Core 23", .gpu),
        "Tg1l": ("GPU Core 24", .gpu),

        // Memory / DRAM
        "Tm01": ("Memory 1", .memory),
        "Tm02": ("Memory 2", .memory),
        "TMVR": ("Memory VRM", .memory),

        // SSD / Storage
        "Ts0S": ("SSD", .ssd),
        "TS0P": ("SSD", .ssd),

        // Battery
        "TB0T": ("Battery 1", .battery),
        "TB1T": ("Battery 2", .battery),
        "TB2T": ("Battery 3", .battery),

        // Airflow
        "TaLP": ("Airflow Left", .airflow),
        "TaRP": ("Airflow Right", .airflow),
        "TaRF": ("Airflow Right", .airflow),
        "TaTP": ("Airflow Total", .airflow),
        "TaLT": ("Left Intake", .airflow),
        "TaRT": ("Right Intake", .airflow),
        "TaLW": ("Left Exhaust", .airflow),
        "TaRW": ("Right Exhaust", .airflow),
        "TAOL": ("Ambient", .airflow),

        // VRM
        "TVD0": ("VRM Die", .vrm),
        "TVA0": ("VRM Ambient", .vrm),

        // Other
        "TW0P": ("Wireless Module", .other),
    ]

    static func nameForKey(_ key: String) -> String {
        catalog[key]?.0 ?? key
    }

    static func categoryForKey(_ key: String) -> SensorCategory {
        if let entry = catalog[key] { return entry.1 }
        if key.hasPrefix("Tp") { return .cpuPerformance }
        if key.hasPrefix("Tg") { return .gpu }
        if key.hasPrefix("Tm") { return .memory }
        if key.hasPrefix("Ts") || key.hasPrefix("TS") { return .ssd }
        if key.hasPrefix("TB") { return .battery }
        if key.hasPrefix("Ta") { return .airflow }
        if key.hasPrefix("TV") { return .vrm }
        return .other
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

    static func cpuCoreSensors(from sensors: [Sensor]) -> [Sensor] {
        sensors.filter {
            let cat = categoryForKey($0.id)
            return cat == .cpuPerformance || cat == .cpuEfficiency
        }
    }

    static func gpuCoreSensors(from sensors: [Sensor]) -> [Sensor] {
        sensors.filter { categoryForKey($0.id) == .gpu }
    }

    static func cpuSummarySensors(from sensors: [Sensor]) -> [Sensor] {
        sensors.filter { categoryForKey($0.id) == .cpuSummary }
    }

    static let defaultCpuSensorKey = "TCMz"
    static let defaultGpuSensorKey = ""
}
