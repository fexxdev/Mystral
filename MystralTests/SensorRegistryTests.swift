import XCTest
@testable import Mystral

final class SensorRegistryTests: XCTestCase {

    func testCpuCoreSensorsFiltering() {
        let sensors = [
            Sensor(id: "Tp01", name: "P1", temperature: 60),
            Sensor(id: "Tp09", name: "E1", temperature: 45),
            Sensor(id: "TCMz", name: "CPU Max", temperature: 65),
            Sensor(id: "Tg0f", name: "GPU Core", temperature: 55),
            Sensor(id: "TB0T", name: "Battery", temperature: 30)
        ]
        let cores = SensorRegistry.cpuCoreSensors(from: sensors)
        XCTAssertTrue(cores.contains(where: { $0.id == "Tp01" }))
        XCTAssertTrue(cores.contains(where: { $0.id == "Tp09" }))
        XCTAssertFalse(cores.contains(where: { $0.id == "TCMz" }))
        XCTAssertFalse(cores.contains(where: { $0.id == "Tg0f" }))
    }

    func testGpuCoreSensorsFiltering() {
        let sensors = [
            Sensor(id: "Tg0f", name: "GPU Core", temperature: 55),
            Sensor(id: "Tg05", name: "GPU Core", temperature: 56),
            Sensor(id: "Tp01", name: "P1", temperature: 60)
        ]
        let gpu = SensorRegistry.gpuCoreSensors(from: sensors)
        XCTAssertEqual(gpu.count, 2)
        XCTAssertFalse(gpu.contains(where: { $0.id == "Tp01" }))
    }

    func testGroupByCategoryReturnsAtLeastOneCategory() {
        let sensors = [Sensor(id: "Tp01", name: "P1", temperature: 60)]
        let grouped = SensorRegistry.groupByCategory(sensors)
        XCTAssertFalse(grouped.isEmpty)
    }

    func testNameForUnknownKeyReturnsKey() {
        // Unknown keys should at least round-trip safely.
        let name = SensorRegistry.nameForKey("ZZZZ")
        XCTAssertFalse(name.isEmpty)
    }

    func testExportDiagnosticDataIncludesSensorsAndFans() {
        let sensors = [Sensor(id: "Tp01", name: "P1", temperature: 60)]
        let fans = [Fan(id: 0, name: "Fan", currentRPM: 1500, targetRPM: 1500, minRPM: 1000, maxRPM: 5000, mode: .auto)]
        let dump = SensorRegistry.exportDiagnosticData(sensors: sensors, fans: fans)
        XCTAssertTrue(dump.contains("Tp01"))
        XCTAssertTrue(dump.contains("1500"))
    }

    func testCpuMaximumFallsBackToSummarySensor() {
        let sensors = [Sensor(id: "TCMz", name: "CPU Max", temperature: 88)]
        XCTAssertEqual(SensorRegistry.cpuMaximumTemperature(from: sensors), 88)
    }

    func testStoppedFanStillCountsAsFanControl() {
        let sensors = [
            Sensor(id: "Tp01", name: "P1", temperature: 60),
            Sensor(id: "TCMz", name: "CPU Max", temperature: 65)
        ]
        let fans = [Fan(id: 0, name: "Fan", currentRPM: 0, targetRPM: 0, minRPM: 1000, maxRPM: 5000, mode: .forced)]
        XCTAssertTrue(SensorRegistry.detectChip(sensors: sensors, fans: fans).hasFanControl)
    }

    func testFanLeftInAutoModeIsNotUnderControl() {
        let fans = [Fan(id: 0, name: "Fan", currentRPM: 2500, targetRPM: 2500, minRPM: 1000, maxRPM: 5000, mode: .auto)]
        XCTAssertFalse(SensorRegistry.detectChip(sensors: [], fans: fans).hasFanControl)
    }

    // MARK: - Plausible readings

    func testPlausibleTemperatureRange() {
        XCTAssertTrue(SensorRegistry.isPlausibleTemperature(45))
        XCTAssertTrue(SensorRegistry.isPlausibleTemperature(10))
        XCTAssertTrue(SensorRegistry.isPlausibleTemperature(130))
        XCTAssertFalse(SensorRegistry.isPlausibleTemperature(1.5), "unpopulated rail")
        XCTAssertFalse(SensorRegistry.isPlausibleTemperature(0))
        XCTAssertFalse(SensorRegistry.isPlausibleTemperature(-40))
        XCTAssertFalse(SensorRegistry.isPlausibleTemperature(150))
        XCTAssertFalse(SensorRegistry.isPlausibleTemperature(.nan))
    }

    // MARK: - History alignment

    func testAlignedHistoryLinesUpOnNewestSample() {
        // "late" appeared two ticks ago, so its samples belong to the last two
        // positions. Index-from-start alignment used to put them at the oldest two.
        let full = Sensor(id: "Tp01", name: "P1", temperature: 50, history: [40, 42, 44, 50])
        let late = Sensor(id: "Tp02", name: "P2", temperature: 70, history: [60, 70])
        let maxes = SensorRegistry.alignedHistory(of: [full, late]) { $0.max() ?? 0 }
        XCTAssertEqual(maxes, [40, 42, 60, 70])
    }

    func testAlignedHistoryEmpty() {
        XCTAssertEqual(SensorRegistry.alignedHistory(of: []) { $0.max() ?? 0 }, [])
    }

    // MARK: - History store

    func testHistorySurvivesShortDropout() {
        var store = SensorHistoryStore()
        var tick1 = [Sensor(id: "Tp01", name: "P1", temperature: 40)]
        store.carry(into: &tick1, maxHistory: 10)
        var tick2: [Sensor] = [] // read dropped this tick
        store.carry(into: &tick2, maxHistory: 10)
        var tick3 = [Sensor(id: "Tp01", name: "P1", temperature: 45)]
        store.carry(into: &tick3, maxHistory: 10)
        // The missed tick repeats the last value, so the history keeps one entry
        // per tick and stays aligned with sensors that never dropped out.
        XCTAssertEqual(tick3[0].history, [40, 40, 45])
    }

    func testHistoryDiscardedAfterLongAbsence() {
        var store = SensorHistoryStore()
        var first = [Sensor(id: "Tp01", name: "P1", temperature: 40)]
        store.carry(into: &first, maxHistory: 10)
        for _ in 0...SensorHistoryStore.maximumMissedTicks {
            var empty: [Sensor] = []
            store.carry(into: &empty, maxHistory: 10)
        }
        var back = [Sensor(id: "Tp01", name: "P1", temperature: 50)]
        store.carry(into: &back, maxHistory: 10)
        XCTAssertEqual(back[0].history, [50])
    }

    func testHistoryRespectsLimit() {
        var store = SensorHistoryStore()
        for t in 0..<5 {
            var s = [Sensor(id: "Tp01", name: "P1", temperature: Double(40 + t))]
            store.carry(into: &s, maxHistory: 3)
            if t == 4 { XCTAssertEqual(s[0].history, [42, 43, 44]) }
        }
    }

    // MARK: - Physical cores vs sensors

    private typealias Level = HardwareInfo.CoreCounts.Level

    /// An M3 Pro reports 48 `Tp` keys and 18 `Tg` keys, but has 11 CPU and 14 GPU cores.
    func testDetectChipReportsPhysicalCoresNotSensorKeys() {
        let sensors = (0..<48).map { Sensor(id: String(format: "Tp%02X", $0), name: "", temperature: 45) }
            + [Sensor(id: "TCMz", name: "CPU Max", temperature: 50)]
        let cores = HardwareInfo.CoreCounts(levels: [Level(name: "Performance", cores: 5), Level(name: "Efficiency", cores: 6)],
                                            total: 11, gpu: 14)
        let chip = SensorRegistry.detectChip(sensors: sensors, fans: [], cores: cores)
        XCTAssertEqual(chip.cores, cores)
        XCTAssertEqual(chip.cpuSensorCount, 48)
    }

    /// The breakdown follows the levels the chip has, whatever the UI language calls them.
    func testCpuCoresTextListsEveryLevel() {
        func text(_ levels: [(String, Int)]) -> String {
            SettingsView.cpuCoresText(.init(levels: levels.map { Level(name: $0.0, cores: $0.1) },
                                            total: levels.reduce(0) { $0 + $1.1 }, gpu: 0))
        }
        let m3Pro = text([("Performance", 5), ("Efficiency", 6)])
        XCTAssertTrue(m3Pro.hasPrefix("11"))
        XCTAssertEqual(m3Pro.components(separatedBy: " + ").count, 2)
        XCTAssertTrue(m3Pro.contains("5 \(SettingsView.localizedLevelName("Performance"))"))
        XCTAssertTrue(m3Pro.contains("6 \(SettingsView.localizedLevelName("Efficiency"))"))

        // M5 Pro: super and performance cores, no efficiency cores.
        let m5Pro = text([("Super", 6), ("Performance", 12)])
        XCTAssertTrue(m5Pro.hasPrefix("18"))
        XCTAssertTrue(m5Pro.contains("6 \(SettingsView.localizedLevelName("Super"))"))
        XCTAssertFalse(m5Pro.contains(SettingsView.localizedLevelName("Efficiency")))

        // M6: three levels.
        let m6 = text([("Super", 2), ("Performance", 4), ("Efficiency", 6)])
        XCTAssertTrue(m6.hasPrefix("12"))
        XCTAssertEqual(m6.components(separatedBy: " + ").count, 3)

        XCTAssertEqual(SettingsView.cpuCoresText(.init(levels: [], total: 8, gpu: 0)), "8")
        XCTAssertEqual(SettingsView.cpuCoresText(.unknown), "—")
    }

    func testThisMacReportsConsistentCoreCounts() {
        let cores = HardwareInfo.coreCounts
        XCTAssertGreaterThan(cores.total, 0)
        if !cores.levels.isEmpty {
            XCTAssertEqual(cores.levels.reduce(0) { $0 + $1.cores }, cores.total)
            XCTAssertFalse(cores.levels.contains { $0.name.isEmpty })
        }
    }

    // MARK: - Chip identity

    private typealias Chip = HardwareInfo.Chip
    private let m1Ultra = Chip(name: "M1 Ultra", levelNames: ["Performance", "Efficiency"])
    private let m3Pro = Chip(name: "M3 Pro", levelNames: ["Performance", "Efficiency"])
    private let m4Pro = Chip(name: "M4 Pro", levelNames: ["Performance", "Efficiency"])
    private let m5 = Chip(name: "M5", levelNames: ["Super", "Efficiency"])
    private let m5Pro = Chip(name: "M5 Pro", levelNames: ["Super", "Performance"])
    private let m6 = Chip(name: "M6", levelNames: ["Super", "Performance", "Efficiency"])
    private let a18Pro = Chip(name: "A18 Pro", levelNames: ["Performance", "Efficiency"])
    private var everyChip: [Chip] { [m1Ultra, m3Pro, m4Pro, m5, m5Pro, m6, a18Pro, .generic] }

    func testChipFromName() {
        XCTAssertEqual(m3Pro.family, 3)
        XCTAssertEqual(m3Pro.tier, .pro)
        XCTAssertEqual(m1Ultra.tier, .ultra)
        XCTAssertEqual(Chip(name: "M4 Max", levelNames: []).tier, .max)
        XCTAssertEqual(m5.tier, .base)
        XCTAssertEqual(m6.family, 6)
        // "A18 Pro" is not an M chip, and its "Pro" is not the M-series Pro tier.
        XCTAssertNil(a18Pro.family)
        XCTAssertEqual(a18Pro.tier, .base)
        XCTAssertNil(Chip(name: "Intel Core i9", levelNames: []).family)
    }

    // MARK: - Key classification

    private func category(_ key: String, _ chip: Chip) -> SensorCategory {
        SensorRegistry.classify(key, chip: chip).category
    }
    private func name(_ key: String, _ chip: Chip) -> String {
        SensorRegistry.classify(key, chip: chip).name
    }

    /// Tp follows CPU load and Tg GPU load in every load capture from M1 to M6.
    func testCpuAndGpuKeysOnEveryChip() {
        for chip in everyChip {
            XCTAssertEqual(category("Tp0C", chip), .cpu)
            XCTAssertEqual(category("Tg0D", chip), .gpu)
        }
    }

    func testCpuClusterNamesFollowTheCoresTheChipHas() {
        XCTAssertEqual(name("Tp0C", m3Pro), "CPU P-Cluster")
        XCTAssertEqual(name("Te05", m3Pro), "CPU E-Cluster")
        XCTAssertEqual(name("Tp00", m5), "CPU Super-Cluster")          // Super + Efficiency
        XCTAssertEqual(name("Tp00", m5Pro), "CPU Super/P-Cluster")     // Super + Performance
        XCTAssertEqual(name("Tp0j", m6), "CPU Super/P-Cluster")
        XCTAssertEqual(name("Te07", m6), "CPU E-Cluster")
        XCTAssertEqual(name("Tp05", a18Pro), "CPU P-Cluster")
        XCTAssertEqual(category("Te05", a18Pro), .cpu)
    }

    /// M1 lays its keys out differently from every later chip.
    func testM1Keys() {
        XCTAssertEqual(name("Tp09", m1Ultra), "CPU E-Cluster")
        XCTAssertEqual(name("Tp09", m3Pro), "CPU P-Cluster")
        XCTAssertEqual(name("Te00", m1Ultra), "CPU Die")
        XCTAssertEqual(category("Tc01", m1Ultra), .cpu)
        XCTAssertEqual(category("TpD3", m1Ultra), .vrm, "TpD keys never follow CPU load")
        XCTAssertEqual(category("TrD2", m1Ultra), .vrm)
        XCTAssertEqual(category("TC12", m1Ultra), .soc)
        XCTAssertEqual(category("Td04", m1Ultra), .soc)
        XCTAssertEqual(category("Tm02", m1Ultra), .memory)
    }

    /// On M5 Pro/Max the 40 Tm keys warm by 14–22 °C under CPU load.
    func testM5ProReusesMemoryKeysForTheCpu() {
        XCTAssertEqual(category("Tm0C", m5Pro), .cpu)
        XCTAssertEqual(name("Tm0C", m5Pro), "CPU P-Cluster")
        XCTAssertEqual(category("Tm0B", m5), .memory)
        XCTAssertEqual(category("Tm0p", m4Pro), .memory)
        XCTAssertEqual(category("Tm0C", m6), .memory)
    }

    func testSocKeys() {
        for chip in everyChip {
            XCTAssertEqual(category("Ts0C", chip), .soc, "Ts keys follow CPU and GPU load on every chip")
            XCTAssertEqual(category("Tf14", chip), .soc)
            XCTAssertEqual(category("Th00", chip), .soc)
        }
        XCTAssertEqual(category("TED0", m3Pro), .soc)
        XCTAssertEqual(category("TUD3", m4Pro), .soc)
        XCTAssertEqual(category("TN00", m5Pro), .soc)
        XCTAssertEqual(category("TQ0d", a18Pro), .soc)
        // M5 and M6: Ta0x warms with the CPU and is not airflow.
        XCTAssertEqual(category("Ta00", m5), .soc)
        XCTAssertEqual(category("Ta0O", m6), .soc)
        XCTAssertEqual(category("Ta0p", m4Pro), .airflow)
        XCTAssertEqual(category("TaLP", m5Pro), .airflow)
    }

    func testStorageKeys() {
        for key in ["Ts0P", "Ts1P", "TsOP", "TS0P", "TS0p", "TH0x", "TH0a", "THSP", "TSDD"] {
            XCTAssertEqual(category(key, m4Pro), .ssd, key)
        }
    }

    func testBatteryKeys() {
        for key in ["TB0T", "TB2T", "TG0B", "TG0V", "TG1B", "TG0H"] {
            XCTAssertEqual(category(key, m3Pro), .battery, key)
        }
        // GPU-style TG keys belong to Intel Macs, and a proximity key is not a cell.
        XCTAssertEqual(category("TG0D", m3Pro), .other)
        XCTAssertEqual(category("TB0p", m1Ultra), .other)
    }

    func testBoardKeys() {
        for key in ["TD00", "TD14", "TDBP", "TDeL", "TT0P", "TIOP", "TW0P", "TR1d", "TaLT", "TSCD"] {
            XCTAssertEqual(category(key, m4Pro), .board, key)
        }
        XCTAssertEqual(name("TaLT", m3Pro), "Thunderbolt Left")
    }

    func testPowerKeys() {
        for key in ["TPD3", "TPDX", "TPMP", "TPSP", "TPH3", "TRD2", "TSVR", "TUVS", "TV01", "TVN1", "TVMN", "TVV0"] {
            XCTAssertEqual(category(key, m5Pro), .vrm, key)
        }
    }

    func testVirtualKeys() {
        XCTAssertEqual(name("TVD0", m3Pro), "CPU Virtual Die")
        XCTAssertEqual(category("TVDG", m5), .soc)
        XCTAssertEqual(category("TVA0", m3Pro), .airflow)
        for key in ["TVM0", "TVm1", "TVh2"] { XCTAssertEqual(category(key, m4Pro), .memory, key) }
        XCTAssertEqual(category("TVS1", m3Pro), .other)
        XCTAssertEqual(name("TVS1", m3Pro), "Virtual Sensor")
    }

    func testSummaryAndOddKeys() {
        XCTAssertEqual(category("TCMz", m3Pro), .cpuSummary)
        XCTAssertEqual(name("TCHP", m3Pro), "CPU Heat Pipe")
        XCTAssertEqual(category("TCHP", m3Pro), .other, "a heat pipe is not a CPU summary value")
        XCTAssertEqual(name("TR0Z", m3Pro), "Calibration Constant")
        // Nobody knows these: they keep their key as name.
        for key in ["TSG1", "T5SP", "ZZZZ"] {
            XCTAssertEqual(name(key, m3Pro), key)
            XCTAssertEqual(category(key, m3Pro), .other)
        }
    }

    func testNoKeyIsNamedAfterASpecificCore() {
        for chip in everyChip {
            for key in ["Tp04", "Tp0C", "Tp1E", "Te05", "Tg0D", "Tm0C"] {
                let name = SensorRegistry.classify(key, chip: chip).name
                XCTAssertFalse(name.contains("Core "), "\(key) → \(name)")
            }
        }
    }

    func testCpuCoreSensorsCoverEveryClusterAndSkipParkedSlots() {
        let sensors = [
            Sensor(id: "Tp0C", name: "", temperature: 55),
            Sensor(id: "Te05", name: "", temperature: 45),
            Sensor(id: "Tp1i", name: "", temperature: 40.0),   // parked bank on M4 Pro/Max
            Sensor(id: "TpD3", name: "", temperature: 38),     // M1 power delivery
            Sensor(id: "Tf14", name: "", temperature: 60),
            Sensor(id: "Ts0C", name: "", temperature: 50)
        ]
        XCTAssertEqual(Set(SensorRegistry.cpuCoreSensors(from: sensors).map(\.id)), ["Tp0C", "Te05"])
    }

    // MARK: - Default fan-curve temperature

    func testDefaultDrivingTemperatureUsesTheDieMaximumWhenPublished() {
        let sensors = [
            Sensor(id: "TCMz", name: "", temperature: 72),
            Sensor(id: "Tp0C", name: "", temperature: 70),
            Sensor(id: "Te05", name: "", temperature: 55)
        ]
        XCTAssertEqual(SensorRegistry.defaultDrivingTemperature(from: sensors), 72)
    }

    /// M5 and M6 publish no TCMz. The curve must still follow the hottest CPU sensor,
    /// not the average, or it would react much later than on older chips.
    func testDefaultDrivingTemperatureWithoutTCMzIsTheHottestCpuSensor() {
        let sensors = [
            Sensor(id: "TCMb", name: "", temperature: 64),
            Sensor(id: "Tp00", name: "", temperature: 81),
            Sensor(id: "Tp0G", name: "", temperature: 67),
            Sensor(id: "Te04", name: "", temperature: 52),
            Sensor(id: "Tg0U", name: "", temperature: 90)   // the GPU must not drive a CPU default
        ]
        XCTAssertEqual(SensorRegistry.defaultDrivingTemperature(from: sensors), 81)
    }

    func testDefaultDrivingTemperatureFallsBackToSummaryThenAnything() {
        XCTAssertEqual(SensorRegistry.defaultDrivingTemperature(from: [Sensor(id: "TCMb", name: "", temperature: 61)]), 61)
        XCTAssertEqual(SensorRegistry.defaultDrivingTemperature(from: [Sensor(id: "TB0T", name: "", temperature: 30)]), 30)
        XCTAssertEqual(SensorRegistry.defaultDrivingTemperature(from: []), 0)
    }
}
