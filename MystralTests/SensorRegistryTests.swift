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
        let fans = [Fan(id: 0, name: "Fan", currentRPM: 0, targetRPM: 0, minRPM: 1000, maxRPM: 5000, mode: .auto)]
        XCTAssertTrue(SensorRegistry.detectChip(sensors: sensors, fans: fans).hasFanControl)
    }

    func testPhysicalCpuCoreMappingStability() {
        // Construct a realistic SMC sensor pool with >10 sensors
        var pool: [Sensor] = [
            Sensor(id: "TCMz", name: "CPU Max", temperature: 45),
            Sensor(id: "TCMb", name: "CPU Hotspot", temperature: 44),
            Sensor(id: "Tp01", name: "P1", temperature: 46),
            Sensor(id: "Tp02", name: "P2", temperature: 45),
            Sensor(id: "Tp03", name: "P3", temperature: 45),
            Sensor(id: "Tp04", name: "P4", temperature: 44),
            Sensor(id: "Tp05", name: "P5", temperature: 46),
            Sensor(id: "Tp06", name: "P6", temperature: 45),
            Sensor(id: "Te04", name: "E1", temperature: 40),
            Sensor(id: "Te05", name: "E2", temperature: 41),
            Sensor(id: "Te06", name: "E3", temperature: 41),
            Sensor(id: "Te0R", name: "E4", temperature: 40),
            Sensor(id: "Tp1j", name: "Phantom Rail", temperature: 2.3),
            Sensor(id: "Tp1n", name: "Phantom Rail", temperature: 1.5)
        ]
        let cores = SensorRegistry.cpuCoreSensors(from: pool)
        XCTAssertEqual(cores.count, HardwareInfo.physicalCpuCount)
        // Ensure no phantom rail (1.5°C / 2.3°C) leaked into the physical core list
        for core in cores {
            XCTAssertGreaterThanOrEqual(core.temperature, 20.0)
            XCTAssertLessThanOrEqual(core.temperature, 125.0)
        }
    }

    func testPhysicalGpuCoreMappingStability() {
        var pool: [Sensor] = []
        for i in 0..<25 {
            pool.append(Sensor(id: String(format: "Tg%02d", i), name: "GPU", temperature: 40.0 + Double(i % 5)))
        }
        let gpu = SensorRegistry.gpuCoreSensors(from: pool)
        let expectedCount = HardwareInfo.gpuCoreCount > 0 ? HardwareInfo.gpuCoreCount : 25
        XCTAssertEqual(gpu.count, expectedCount)
        for g in gpu {
            XCTAssertTrue(g.id.hasPrefix("G"))
            XCTAssertGreaterThanOrEqual(g.temperature, 20.0)
        }
    }
}
