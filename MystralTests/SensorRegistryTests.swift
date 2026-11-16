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

    /// An M3 Pro reports 48 `Tp` keys and 18 `Tg` keys, but has 11 CPU and 14 GPU cores.
    func testDetectChipReportsPhysicalCoresNotSensorKeys() {
        let sensors = (0..<48).map { Sensor(id: String(format: "Tp%02X", $0), name: "", temperature: 45) }
            + [Sensor(id: "TCMz", name: "CPU Max", temperature: 50)]
        let cores = HardwareInfo.CoreCounts(performance: 5, efficiency: 6, total: 11, gpu: 14)
        let chip = SensorRegistry.detectChip(sensors: sensors, fans: [], cores: cores)
        XCTAssertEqual(chip.cores, cores)
        XCTAssertEqual(chip.cpuSensorCount, 48)
    }

    func testCpuCoresText() {
        XCTAssertEqual(SettingsView.cpuCoresText(.init(performance: 5, efficiency: 6, total: 11, gpu: 14)), "11 (5 P + 6 E)")
        XCTAssertEqual(SettingsView.cpuCoresText(.init(performance: 0, efficiency: 0, total: 8, gpu: 0)), "8")
        XCTAssertEqual(SettingsView.cpuCoresText(.unknown), "—")
    }

    /// Apple Silicon has no SMT: every core is either a P-core or an E-core.
    func testThisMacReportsConsistentCoreCounts() {
        let cores = HardwareInfo.coreCounts
        XCTAssertGreaterThan(cores.total, 0)
        if cores.performance > 0, cores.efficiency > 0 {
            XCTAssertEqual(cores.performance + cores.efficiency, cores.total)
        }
    }

    // MARK: - Key classification

    private func category(_ key: String, family: Int? = 3) -> SensorCategory {
        SensorRegistry.classify(key, chipFamily: family).category
    }

    /// Load tests on an M3 Pro (Mac15,6): Tp follows P-core load, Te is the only group
    /// that warms under an E-core-only load, Tg follows the GPU, Tf and Ts0x follow
    /// both and are SoC sensors.
    func testM3ProKeyGroups() {
        XCTAssertEqual(category("Tp0C"), .cpuPerformance)
        XCTAssertEqual(category("Te0H"), .cpuEfficiency)
        XCTAssertEqual(category("Tg0D"), .gpu)
        XCTAssertEqual(category("Tf14"), .soc)
        XCTAssertEqual(category("Tf24"), .soc)
        XCTAssertEqual(category("Ts0C"), .soc, "Ts0x warms +20 °C under GPU load: not an SSD")
        XCTAssertEqual(category("TED0"), .soc)
        XCTAssertEqual(category("TD00"), .soc)
    }

    func testStorageBatteryAndEnclosureKeys() {
        XCTAssertEqual(category("Ts0P"), .ssd)
        XCTAssertEqual(category("TS0P"), .ssd)
        XCTAssertEqual(category("TH0x"), .ssd)
        XCTAssertEqual(category("Th00"), .other, "lowercase h is a heatsink, not NAND")
        XCTAssertEqual(category("TG0B"), .battery, "uppercase G is the gas gauge, not the GPU")
        XCTAssertEqual(category("TB0T"), .battery)
        XCTAssertEqual(SensorRegistry.classify("TaLT", chipFamily: 3).name, "Thunderbolt Left")
        XCTAssertEqual(SensorRegistry.classify("TCHP", chipFamily: 3).name, "CPU Heat Pipe")
        XCTAssertEqual(category("TCHP"), .other, "a heat pipe is not a CPU summary value")
        XCTAssertEqual(category("TPD3"), .vrm)
        XCTAssertEqual(category("TPMP"), .other)
    }

    func testM1KeysDiffer() {
        XCTAssertEqual(category("Tp09", family: 1), .cpuEfficiency)
        XCTAssertEqual(category("Tp09", family: 2), .cpuPerformance)
        XCTAssertEqual(category("Te00", family: 1), .cpuSummary)
        XCTAssertEqual(category("Te04", family: 2), .cpuEfficiency)
    }

    func testNoKeyIsNamedAfterASpecificCore() {
        for key in ["Tp04", "Tp0C", "Tp1E", "Te05", "Tg0D"] {
            let name = SensorRegistry.classify(key, chipFamily: 3).name
            XCTAssertFalse(name.contains("Core "), "\(key) → \(name)")
        }
    }

    func testCpuCoreSensorsCoverBothClustersAndSkipParkedSlots() {
        let sensors = [
            Sensor(id: "Tp0C", name: "", temperature: 55),
            Sensor(id: "Te05", name: "", temperature: 45),
            Sensor(id: "Tp1i", name: "", temperature: 40.0),   // parked bank on M4 Pro/Max
            Sensor(id: "Tf14", name: "", temperature: 60),
            Sensor(id: "Ts0C", name: "", temperature: 50)
        ]
        XCTAssertEqual(Set(SensorRegistry.cpuCoreSensors(from: sensors).map(\.id)), ["Tp0C", "Te05"])
    }

    func testChipFamilyFromName() {
        XCTAssertEqual(HardwareInfo.family(fromChipName: "M3 Pro"), 3)
        XCTAssertEqual(HardwareInfo.family(fromChipName: "M1"), 1)
        XCTAssertEqual(HardwareInfo.family(fromChipName: "M4 Max"), 4)
        XCTAssertNil(HardwareInfo.family(fromChipName: "Intel Core i9"))
        XCTAssertNil(HardwareInfo.family(fromChipName: ""))
    }
}
