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
        var tick1 = [Sensor(id: "TB0T", name: "Battery", temperature: 40)]
        store.carry(into: &tick1, maxHistory: 10)
        var tick2: [Sensor] = [] // read dropped this tick
        store.carry(into: &tick2, maxHistory: 10)
        var tick3 = [Sensor(id: "TB0T", name: "Battery", temperature: 45)]
        store.carry(into: &tick3, maxHistory: 10)
        // The missed tick repeats the last value, so the history keeps one entry
        // per tick and stays aligned with sensors that never dropped out.
        XCTAssertEqual(tick3[0].history, [40, 40, 45])
    }

    func testHistoryDiscardedAfterLongAbsence() {
        var store = SensorHistoryStore()
        var first = [Sensor(id: "TB0T", name: "Battery", temperature: 40)]
        store.carry(into: &first, maxHistory: 10)
        for _ in 0...SensorHistoryStore.maximumMissedTicks {
            var empty: [Sensor] = []
            store.carry(into: &empty, maxHistory: 10)
        }
        var back = [Sensor(id: "TB0T", name: "Battery", temperature: 50)]
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
    func testCpuDescriptionListsEveryLevel() {
        func text(_ levels: [(String, Int)]) -> String {
            HardwareInfo.CoreCounts(levels: levels.map { Level(name: $0.0, cores: $0.1) },
                                    total: levels.reduce(0) { $0 + $1.1 }, gpu: 0).cpuDescription
        }
        let m3Pro = text([("Performance", 5), ("Efficiency", 6)])
        XCTAssertTrue(m3Pro.hasPrefix("11"))
        XCTAssertEqual(m3Pro.components(separatedBy: " + ").count, 2)
        XCTAssertTrue(m3Pro.contains("5 \(Level(name: "Performance", cores: 0).localizedName)"))
        XCTAssertTrue(m3Pro.contains("6 \(Level(name: "Efficiency", cores: 0).localizedName)"))

        // M5 Pro: super and performance cores, no efficiency cores.
        let m5Pro = text([("Super", 6), ("Performance", 12)])
        XCTAssertTrue(m5Pro.hasPrefix("18"))
        XCTAssertTrue(m5Pro.contains("6 \(Level(name: "Super", cores: 0).localizedName)"))
        XCTAssertFalse(m5Pro.contains(Level(name: "Efficiency", cores: 0).localizedName))

        // M6: three levels.
        let m6 = text([("Super", 2), ("Performance", 4), ("Efficiency", 6)])
        XCTAssertTrue(m6.hasPrefix("12"))
        XCTAssertEqual(m6.components(separatedBy: " + ").count, 3)

        XCTAssertEqual(HardwareInfo.CoreCounts(levels: [], total: 8, gpu: 0).cpuDescription, "8")
        XCTAssertEqual(HardwareInfo.CoreCounts.unknown.cpuDescription, "—")
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

    /// When the two key banks of an M4 Pro swap, TCMz lags for a tick (82 °C against a
    /// hottest live sensor at 97 °C in iSMC's recording).
    func testDefaultDrivingTemperatureIsNeverBelowTheHottestCpuSensor() {
        let sensors = [
            Sensor(id: "TCMz", name: "", temperature: 82.3),
            Sensor(id: "Tp0E", name: "", temperature: 97.1),
            Sensor(id: "Tg0D", name: "", temperature: 99)
        ]
        XCTAssertEqual(SensorRegistry.defaultDrivingTemperature(from: sensors), 97.1)
    }

    func testDefaultDrivingTemperatureFallsBackToSummaryThenAnything() {
        XCTAssertEqual(SensorRegistry.defaultDrivingTemperature(from: [Sensor(id: "TCMb", name: "", temperature: 61)]), 61)
        XCTAssertEqual(SensorRegistry.defaultDrivingTemperature(from: [Sensor(id: "TB0T", name: "", temperature: 30)]), 30)
        XCTAssertEqual(SensorRegistry.defaultDrivingTemperature(from: []), 0)
    }

    // MARK: - CPU keys the SMC switches off (issue #8, M4 Pro)

    /// On M4 Pro the performance cluster publishes two banks of 51 keys. `bankA` and
    /// `bankB` stand in for them here with three keys each.
    private let bankA = ["Tp00", "Tp01", "Tp02"]
    private let bankB = ["Tp1i", "Tp1j", "Tp1k"]
    private let efficiency = ["Te04", "Te05"]

    private func tick(_ store: inout SensorHistoryStore, _ readings: [String: Double]) -> [Sensor] {
        var sensors = readings.keys.sorted().map { Sensor(id: $0, name: "", temperature: readings[$0]!) }
        store.carry(into: &sensors, maxHistory: 20)
        return sensors
    }

    private func readings(_ keys: [String], _ value: Double) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, value) })
    }

    /// Reported sequence: 61 CPU sensors, then 10 for one tick, then 61 again.
    func testCpuKeysAreHeldWhileTheClusterIsOffForATick() {
        var store = SensorHistoryStore()
        _ = tick(&store, readings(bankA, 77).merging(readings(efficiency, 60)) { $1 })
        // Both banks off: A is absent (it reads below 10 °C and is dropped), B was never live.
        let gap = tick(&store, readings(efficiency, 61))
        XCTAssertEqual(gap.map(\.id), (bankA + efficiency).sorted(), "held keys keep their place in the list")
        for id in bankA {
            let sensor = gap.first { $0.id == id }
            XCTAssertEqual(sensor?.temperature, 77)
            XCTAssertEqual(sensor?.isHeld, true)
        }
        XCTAssertEqual(gap.first { $0.id == "Te04" }?.isHeld, false)
        XCTAssertEqual(SensorRegistry.cpuCoreSensors(from: gap).count, 5)
        XCTAssertEqual(SensorRegistry.cpuMaximumTemperature(from: gap), 77)

        let back = tick(&store, readings(bankA, 74).merging(readings(efficiency, 60)) { $1 })
        XCTAssertFalse(back.contains { $0.isHeld })
        XCTAssertEqual(back.first { $0.id == "Tp00" }?.history, [77, 77, 74])
    }

    /// A parked key reads exactly 40.0 °C. It shows its last live reading instead.
    func testParkedKeysShowTheirLastLiveReading() {
        var store = SensorHistoryStore()
        _ = tick(&store, readings(bankA, 70).merging(readings(efficiency, 55)) { $1 })
        var next = readings(bankA, 71).merging(readings(efficiency, 55)) { $1 }
        next["Tp02"] = SensorRegistry.parkedCpuReading
        let sensors = tick(&store, next)
        XCTAssertEqual(sensors.first { $0.id == "Tp02" }?.temperature, 70)
        XCTAssertEqual(sensors.first { $0.id == "Tp02" }?.isHeld, true)
        XCTAssertEqual(SensorRegistry.cpuCoreSensors(from: sensors).count, 5)
    }

    /// When the other bank takes over, as many keys are live as before, so nothing
    /// is held and the two banks are never listed side by side.
    func testBankSwitchDoesNotDoubleTheSensors() {
        var store = SensorHistoryStore()
        _ = tick(&store, readings(bankA, 70).merging(readings(efficiency, 55)) { $1 })
        let switched = tick(&store, readings(bankB, 72).merging(readings(efficiency, 55)) { $1 })
        XCTAssertEqual(switched.map(\.id), (bankB + efficiency).sorted())
        XCTAssertFalse(switched.contains { $0.isHeld })
    }

    /// After a bank switch, a gap is filled with the bank that was live last.
    func testGapAfterBankSwitchHoldsTheMostRecentBank() {
        var store = SensorHistoryStore()
        _ = tick(&store, readings(bankA, 70).merging(readings(efficiency, 55)) { $1 })
        _ = tick(&store, readings(bankB, 72).merging(readings(efficiency, 55)) { $1 })
        let gap = tick(&store, readings(efficiency, 55))
        XCTAssertEqual(gap.filter(\.isHeld).map(\.id), bankB)
    }

    /// A cluster that stays off is really off: the held readings expire.
    func testHeldReadingsExpire() {
        var store = SensorHistoryStore()
        _ = tick(&store, readings(bankA, 70).merging(readings(efficiency, 55)) { $1 })
        for _ in 0..<SensorHistoryStore.maximumMissedTicks {
            XCTAssertEqual(tick(&store, readings(efficiency, 55)).filter(\.isHeld).count, bankA.count)
        }
        let expired = tick(&store, readings(efficiency, 55))
        XCTAssertEqual(expired.map(\.id), efficiency)
    }

    /// The hold lasts about ten seconds whatever the polling interval is.
    func testHoldLastsAboutTenSecondsAtEveryPollingInterval() {
        XCTAssertEqual(SensorHistoryStore.cpuHoldTicks(forPollingInterval: 2), 5)
        XCTAssertEqual(SensorHistoryStore.cpuHoldTicks(forPollingInterval: 5), 2)
        XCTAssertEqual(SensorHistoryStore.cpuHoldTicks(forPollingInterval: 10), 1)

        var store = SensorHistoryStore()
        func step(_ readings: [String: Double]) -> [Sensor] {
            var sensors = readings.keys.sorted().map { Sensor(id: $0, name: "", temperature: readings[$0]!) }
            store.carry(into: &sensors, maxHistory: 20, cpuHoldTicks: 1)
            return sensors
        }
        _ = step(readings(bankA, 70).merging(readings(efficiency, 55)) { $1 })
        XCTAssertEqual(step(readings(efficiency, 55)).filter(\.isHeld).count, bankA.count)
        XCTAssertEqual(step(readings(efficiency, 55)).filter(\.isHeld).count, 0)
    }

    /// Under heavy load both banks are live; when one goes off its keys are held, then
    /// dropped, and they are not brought back while the other bank carries on.
    func testBankGoingOffAfterBothWereLive() {
        var store = SensorHistoryStore()
        let both = readings(bankA, 90).merging(readings(bankB, 88)) { $1 }.merging(readings(efficiency, 60)) { $1 }
        XCTAssertEqual(tick(&store, both).count, 8)
        let oneBank = readings(bankB, 80).merging(readings(efficiency, 60)) { $1 }
        for _ in 0..<SensorHistoryStore.maximumMissedTicks {
            XCTAssertEqual(tick(&store, oneBank).filter(\.isHeld).map(\.id), bankA)
        }
        XCTAssertEqual(tick(&store, oneBank).map(\.id), (bankB + efficiency).sorted())
        XCTAssertFalse(tick(&store, oneBank).contains { $0.isHeld })
    }

    /// Issue #8, trace from a real M4 Pro: after both banks had been live once, the
    /// banks took turns every 1–3 ticks with one-tick gaps, and the count stayed at both
    /// banks for ten minutes. It must settle at one bank once the hold window has passed.
    func testAlternatingBanksSettleAtOneBankAfterBothWereLive() {
        var store = SensorHistoryStore()
        let e = readings(efficiency, 60)
        let a = readings(bankA, 70).merging(e) { $1 }
        let b = readings(bankB, 72).merging(e) { $1 }
        _ = tick(&store, a.merging(b) { $1 })

        // Within the hold window the bank that just went off is still shown.
        XCTAssertEqual(tick(&store, a).filter(\.isHeld).map(\.id), bankB)
        XCTAssertEqual(tick(&store, b).filter(\.isHeld).map(\.id), bankA)
        for readings in [a, a, b] { _ = tick(&store, readings) }

        // Past it, each bank shows alone, and a gap is filled with the last one only.
        for _ in 0..<20 {
            XCTAssertEqual(tick(&store, a).map(\.id), (bankA + efficiency).sorted())
            XCTAssertEqual(tick(&store, a).filter(\.isHeld).count, 0)
            XCTAssertEqual(tick(&store, e).filter(\.isHeld).map(\.id), bankA)
            XCTAssertEqual(tick(&store, b).map(\.id), (bankB + efficiency).sorted())
            XCTAssertEqual(tick(&store, e).filter(\.isHeld).map(\.id), bankB)
            XCTAssertEqual(tick(&store, b).filter(\.isHeld).count, 0)
        }
    }

    /// The hold window follows the polling interval when it changes.
    func testHoldWindowShrinksWithTheHoldTicks() {
        var store = SensorHistoryStore()
        func step(_ readings: [String: Double], holdTicks: Int) -> [Sensor] {
            var sensors = readings.keys.sorted().map { Sensor(id: $0, name: "", temperature: readings[$0]!) }
            store.carry(into: &sensors, maxHistory: 20, cpuHoldTicks: holdTicks)
            return sensors
        }
        let e = readings(efficiency, 60)
        _ = step(readings(bankA, 70).merging(e) { $1 }, holdTicks: 5)
        XCTAssertEqual(step(e, holdTicks: 5).filter(\.isHeld).count, bankA.count)
        XCTAssertEqual(step(e, holdTicks: 1).filter(\.isHeld).count, 0)
    }

    // MARK: - Held readings and the fan curve (issue #8, second report)

    /// A held reading counts as current for about four seconds. After that the key
    /// stays listed, so the count does not jump, but it is out of the maximum and average.
    func testHeldReadingsGoStaleAfterTheFreshWindow() {
        XCTAssertEqual(SensorHistoryStore.cpuFreshTicks(forPollingInterval: 2), 2)
        XCTAssertEqual(SensorHistoryStore.cpuFreshTicks(forPollingInterval: 5), 1)
        XCTAssertEqual(SensorHistoryStore.cpuFreshTicks(forPollingInterval: 10), 1)

        var store = SensorHistoryStore()
        _ = tick(&store, readings(bankA, 71).merging(readings(efficiency, 46)) { $1 })
        for age in 1...SensorHistoryStore.maximumMissedTicks {
            let gap = tick(&store, readings(efficiency, 46))
            let held = gap.filter(\.isHeld)
            XCTAssertEqual(held.map(\.id), bankA, "listed for the whole hold")
            XCTAssertEqual(held.allSatisfy(\.isStale), age > 2, "age \(age)")
            XCTAssertEqual(SensorRegistry.cpuCoreSensors(from: gap).count, 5)
            XCTAssertEqual(SensorRegistry.cpuCurrentSensors(from: gap).count, age > 2 ? 2 : 5)
            XCTAssertEqual(SensorRegistry.cpuMaximumTemperature(from: gap), age > 2 ? 46 : 71)
            XCTAssertEqual(SensorRegistry.cpuAverageTemperature(from: gap), age > 2 ? 46 : 61)
        }
    }

    func testDrivingReadingIsHeldWhileTheHotSpotIsOff() {
        var store = SensorHistoryStore()
        let live = tick(&store, readings(bankA, 93).merging(["Te04": 72, "TCMz": 93]) { $1 })
        XCTAssertEqual(SensorRegistry.drivingReading(forProfileSensor: "", from: live),
                       .init(temperature: 93, isHeld: false))
        for _ in 0..<2 {
            let gap = tick(&store, ["Te04": 72, "TCMz": 72])
            XCTAssertEqual(SensorRegistry.drivingReading(forProfileSensor: "", from: gap),
                           .init(temperature: 93, isHeld: true))
        }
        // Past the fresh window the load has ended: the live reading is the measurement.
        let idle = tick(&store, ["Te04": 72, "TCMz": 72])
        XCTAssertEqual(SensorRegistry.drivingReading(forProfileSensor: "", from: idle),
                       .init(temperature: 72, isHeld: false))
    }

    /// One bank goes off after both were live. If the live bank is the hotter one,
    /// the hot spot is being measured and nothing is paused.
    func testDrivingReadingIsLiveWhenTheLiveBankIsHotter() {
        var store = SensorHistoryStore()
        let e = readings(efficiency, 60)
        _ = tick(&store, readings(bankA, 80).merging(readings(bankB, 90)) { $1 }.merging(e) { $1 })
        let hotterLive = tick(&store, readings(bankB, 91).merging(e) { $1 })
        XCTAssertEqual(hotterLive.filter(\.isHeld).map(\.id), bankA)
        XCTAssertEqual(SensorRegistry.drivingReading(forProfileSensor: "", from: hotterLive),
                       .init(temperature: 91, isHeld: false))

        var other = SensorHistoryStore()
        _ = tick(&other, readings(bankA, 95).merging(readings(bankB, 90)) { $1 }.merging(e) { $1 })
        let hotterHeld = tick(&other, readings(bankB, 91).merging(e) { $1 })
        XCTAssertEqual(SensorRegistry.drivingReading(forProfileSensor: "", from: hotterHeld),
                       .init(temperature: 95, isHeld: true))
    }

    /// TCMz and TCMb fall with the cluster, so a profile that names one is held under
    /// the same condition. A sensor outside the CPU never is.
    func testProfileSensorsAndTheHeldHotSpot() {
        var store = SensorHistoryStore()
        _ = tick(&store, readings(bankA, 93).merging(["Te04": 72, "TCMz": 93, "TCMb": 74, "Tg0D": 55]) { $1 })
        let gap = tick(&store, ["Te04": 72, "TCMz": 72, "TCMb": 68, "Tg0D": 56])
        XCTAssertEqual(SensorRegistry.drivingReading(forProfileSensor: "TCMz", from: gap), .init(temperature: 72, isHeld: true))
        XCTAssertEqual(SensorRegistry.drivingReading(forProfileSensor: "TCMb", from: gap), .init(temperature: 68, isHeld: true))
        XCTAssertEqual(SensorRegistry.drivingReading(forProfileSensor: "Tp00", from: gap), .init(temperature: 93, isHeld: true))
        XCTAssertEqual(SensorRegistry.drivingReading(forProfileSensor: "Tg0D", from: gap), .init(temperature: 56, isHeld: false))
        XCTAssertEqual(SensorRegistry.drivingReading(forProfileSensor: "ZZZZ", from: gap), .init(temperature: 93, isHeld: true),
                       "a missing sensor means the default")

        _ = tick(&store, ["Te04": 72, "TCMz": 72])
        let stale = tick(&store, ["Te04": 72, "TCMz": 72])
        XCTAssertEqual(SensorRegistry.drivingReading(forProfileSensor: "Tp00", from: stale), .init(temperature: 72, isHeld: false),
                       "a stale sensor means the default")
    }

    func testCurveInputKeepsItsValueWhileTheReadingIsHeld() {
        let halve: (Double) -> Double = { $0 / 2 }
        XCTAssertEqual(FanController.curveInput(for: .init(temperature: 90, isHeld: false), previous: 60, smoothed: halve), 45)
        XCTAssertEqual(FanController.curveInput(for: .init(temperature: 90, isHeld: true), previous: 60, smoothed: halve), 60)
        XCTAssertEqual(FanController.curveInput(for: .init(temperature: 90, isHeld: true), previous: nil, smoothed: halve), 45)
    }

    /// The store, the driving reading and the curve input together, with the default
    /// smoothing (alpha 0.3), on the three cases measured on an M4 Pro.
    private func curveInputs(_ ticks: [[String: Double]]) -> [Double] {
        var store = SensorHistoryStore()
        var smoothedValue: Double?
        var previous: Double?
        return ticks.map { readings in
            let sensors = tick(&store, readings)
            let reading = SensorRegistry.drivingReading(forProfileSensor: "", from: sensors)
            let input = FanController.curveInput(for: reading, previous: previous) { raw in
                let next = smoothedValue.map { 0.3 * raw + 0.7 * $0 } ?? raw
                smoothedValue = next
                return next
            }
            previous = input
            return input
        }
    }

    private func on(_ temperature: Double, efficiency e: Double) -> [String: Double] {
        readings(bankA, temperature).merging(["Te04": e, "TCMz": temperature]) { $1 }
    }

    private func off(efficiency e: Double) -> [String: Double] { ["Te04": e, "TCMz": e] }

    /// Steady load with a one-tick gap every fourth tick (iSMC's M4 Pro recording:
    /// 93 → 72.6 → 93 °C). The curve input must not move.
    func testCurveInputDoesNotDipInShortGaps() {
        let ticks = (0..<40).map { $0 % 4 == 3 ? off(efficiency: 72.6) : on(93, efficiency: 72.6) }
        for input in curveInputs(ticks) { XCTAssertEqual(input, 93, accuracy: 0.001) }
    }

    /// A one-tick spike followed by idle. Held for ten seconds, the spike weighed 83%
    /// on the curve input instead of 30% and the fans rose for ten seconds. It must
    /// weigh what one sample weighs.
    func testSpikeBeforeIdleIsNotAmplified() {
        let ticks = Array(repeating: on(50, efficiency: 46), count: 10) + [on(71, efficiency: 46)]
            + Array(repeating: off(efficiency: 46), count: 8)
        let inputs = curveInputs(ticks)
        XCTAssertEqual(inputs[10], 56.3, accuracy: 0.001)
        XCTAssertEqual(inputs.max() ?? 0, 56.3, accuracy: 0.001, "the spike is counted once")
        XCTAssertEqual(Array(inputs[11...12]), [56.3, 56.3], "paused for the fresh window")
        XCTAssertLessThan(inputs[13], 56.3)
        XCTAssertLessThan(inputs.last ?? 100, 48)
    }

    /// The load ends at 113.8 °C with the live reading at 64.4 °C (reported on an M4
    /// Pro). The input may keep its value for the fresh window, about four seconds,
    /// not ten, and then comes down through the filter without a step.
    func testCurveInputComesDownAfterTheLoadEnds() {
        let ticks = Array(repeating: on(113.8, efficiency: 64.4), count: 20)
            + Array(repeating: off(efficiency: 64.4), count: 12)
        let inputs = curveInputs(ticks)
        XCTAssertEqual(Array(inputs[20...21]), [113.8, 113.8])
        XCTAssertEqual(inputs[22], 0.3 * 64.4 + 0.7 * 113.8, accuracy: 0.001)
        let falls = zip(inputs[21...], inputs[22...]).map { $0 - $1 }
        XCTAssertLessThanOrEqual(falls.max() ?? 0, 0.3 * (113.8 - 64.4) + 0.001, "no fall larger than the filter's own")
        XCTAssertLessThan(inputs.last ?? 100, 67)
    }

    func testOnlyCpuKeysAreHeld() {
        var store = SensorHistoryStore()
        _ = tick(&store, ["Tp00": 70, "Tg0D": 50, "TB0T": 30])
        let next = tick(&store, ["Tp00": 70])
        XCTAssertEqual(next.map(\.id), ["Tp00"])
    }

    /// TCMz is the maximum over live keys, so it collapses with the cluster
    /// (77 → 62 → 73 °C across three ticks in the report). The curve must not follow it down.
    func testDefaultDrivingTemperatureBridgesTheGap() {
        var store = SensorHistoryStore()
        _ = tick(&store, readings(bankA, 77).merging(["Te04": 62, "TCMz": 77]) { $1 })
        let gap = tick(&store, ["Te04": 62, "TCMz": 62])
        XCTAssertEqual(SensorRegistry.defaultDrivingTemperature(from: gap), 77)
        let back = tick(&store, readings(bankA, 73).merging(["Te04": 62, "TCMz": 73]) { $1 })
        XCTAssertEqual(SensorRegistry.defaultDrivingTemperature(from: back), 73)
    }

    /// Tpx… and Tex… repeat group maxima (Tex1 == Te06, Tpx1 == Tp0E on an M4 Pro):
    /// summaries, not more probes to average.
    func testDieAggregatesAreSummariesNotClusterSensors() {
        for key in ["Tpx0", "Tpx1", "TpxD", "Tex0", "Tex3"] {
            XCTAssertEqual(category(key, m4Pro), .cpuSummary, key)
            XCTAssertEqual(name(key, m4Pro), "CPU Die Aggregate")
        }
        XCTAssertEqual(category("Tsx0", m4Pro), .soc)
        let sensors = [Sensor(id: "Tp0E", name: "", temperature: 98), Sensor(id: "Tpx1", name: "", temperature: 98)]
        XCTAssertEqual(SensorRegistry.cpuCoreSensors(from: sensors).map(\.id), ["Tp0E"])
    }

    /// The Dashboard box shows the three whole-CPU values, not every summary key.
    func testHeadlineSummaryIsThreeKeysInOrder() {
        let sensors = ["Tpx1", "TCDX", "Tex0", "TCMz", "TCMb"].map { Sensor(id: $0, name: "", temperature: 50) }
        XCTAssertEqual(SensorRegistry.cpuSummarySensors(from: sensors).map(\.id), ["TCMz", "TCMb", "TCDX"])
    }
}
