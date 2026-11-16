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
}
