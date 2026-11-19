import XCTest
@testable import Mystral

final class SensorTraceTests: XCTestCase {
    private func sensor(_ id: String, _ temperature: Double, held: Bool = false) -> Sensor {
        Sensor(id: id, name: id, temperature: temperature, isHeld: held)
    }

    private func fan(_ rpm: Int) -> Fan {
        Fan(id: 0, name: "Fan", currentRPM: rpm, targetRPM: rpm, minRPM: 1000, maxRPM: 5000, mode: .forced)
    }

    func testEntryCountsLiveParkedAndHeldKeys() {
        // The performance keys are off: one parked at 40.0, one dropped by the helper.
        let raw = [sensor("TCMz", 72.5), sensor("Te04", 71), sensor("Te05", 72.5), sensor("Tp00", 40.0)]
        var stale = sensor("Tp01", 95, held: true)
        stale.isStale = true
        let shown = [sensor("TCMz", 72.5), sensor("Te04", 71), sensor("Te05", 72.5), sensor("Tp00", 93, held: true), stale]
        let entry = SensorTrace.entry(raw: raw, shown: shown, driving: .init(temperature: 93, isHeld: true),
                                      curveInput: 90.4, fans: [fan(2300)], targetPercent: [41.5],
                                      cpuWatts: 1.1, gpuWatts: nil)

        XCTAssertEqual(entry.live, 2)
        XCTAssertEqual(entry.parked, 1)
        XCTAssertEqual(entry.held, 2)
        XCTAssertEqual(entry.heldCurrent, 1)
        XCTAssertEqual(entry.firstLiveKey, "Te04")
        XCTAssertEqual(entry.lastLiveKey, "Te05")
        XCTAssertEqual(entry.hottestLiveKey, "Te05")
        XCTAssertEqual(entry.liveMaximum, 72.5)
        XCTAssertNil(entry.performanceMaximum)
        XCTAssertEqual(entry.efficiencyMaximum, 72.5)
        XCTAssertEqual(entry.dieMaximum, 72.5)
        XCTAssertEqual(entry.heldMaximum, 95, "stale readings included: what holding everything would use")
        XCTAssertEqual(entry.shownMaximum, 93, "stale readings are not shown as the maximum")
        XCTAssertEqual(entry.shownAverage ?? 0, (71 + 72.5 + 93) / 3, accuracy: 0.001)
        XCTAssertEqual(entry.driving, 93)
        XCTAssertTrue(entry.isDrivingHeld)
        XCTAssertEqual(entry.curveInput, 90.4)
        XCTAssertEqual(entry.targetPercent, [41.5])
        XCTAssertEqual(entry.fanRPM, [2300])
        XCTAssertEqual(entry.cpuWatts, 1.1)
        XCTAssertNil(entry.gpuWatts)
    }

    func testEntryWithoutCpuKeysHasNoLiveValues() {
        let entry = SensorTrace.entry(raw: [sensor("TB0T", 30)], shown: [sensor("TB0T", 30)], driving: nil, curveInput: nil, fans: [])
        XCTAssertEqual(entry.live, 0)
        XCTAssertNil(entry.firstLiveKey)
        XCTAssertNil(entry.liveMaximum)
        XCTAssertNil(entry.dieMaximum)
    }

    func testTraceKeepsTheNewestEntries() {
        var trace = SensorTrace()
        for i in 0..<(SensorTrace.capacity + 20) {
            trace.record(SensorTrace.entry(raw: [], shown: [], driving: nil, curveInput: Double(i), fans: []))
        }
        XCTAssertEqual(trace.entries.count, SensorTrace.capacity)
        XCTAssertEqual(trace.entries.first?.curveInput, 20)
        XCTAssertEqual(trace.entries.last?.curveInput, Double(SensorTrace.capacity + 19))
    }

    private func settings(interval: TimeInterval = 2, sensor: String = "", curve: [CurvePoint] = [],
                          alpha: Double? = 0.3, minimum: Double = 0) -> SensorTrace.Settings {
        .init(pollingInterval: interval, curveSensor: sensor, curve: curve, smoothingAlpha: alpha, minimumFanPercentage: minimum)
    }

    func testReportHasOneLinePerTick() {
        var trace = SensorTrace()
        let raw = [sensor("TCMz", 93.1), sensor("Te04", 70), sensor("Tp0w", 93.1), sensor("Tp1i", 40.0)]
        trace.record(SensorTrace.entry(raw: raw, shown: raw, driving: .init(temperature: 93.1, isHeld: false),
                                       curveInput: 91.84, fans: [fan(2310), fan(2290)], targetPercent: [40, nil],
                                       cpuWatts: 12.34, gpuWatts: 0.5))
        trace.record(SensorTrace.entry(raw: [], shown: [], driving: nil, curveInput: nil, fans: []))

        let curve = [CurvePoint(temperature: 80, fanPercentage: 100), CurvePoint(temperature: 40, fanPercentage: 0)]
        let report = trace.report(settings(curve: curve))
        XCTAssertEqual(report.count, 6)
        XCTAssertEqual(report[0], "=== CPU Sensor Trace (2 ticks, oldest first) ===")
        XCTAssertEqual(report[1], "Polling interval: 2.0 s | hold: 5 ticks | current: 2 ticks | curve sensor: default (hottest CPU point)")
        XCTAssertEqual(report[2], "Smoothing: on (alpha 0.30) | minimum fan: 0.0 % | curve: 40.0°→0.0% 80.0°→100.0%")
        XCTAssertEqual(report[3], SensorTrace.columns.joined(separator: " | "))
        XCTAssertTrue(report[4].hasSuffix(
            " | 2 | 1 | 0 | 0 | Te04…Tp0w | Tp0w | 93.1 | 93.1 | 70.0 | - | 93.1 | 81.5 | 93.1 | no | 91.8 | 40.0/- | 2310/2290 | 12.3 | 0.5"),
            report[4])
        XCTAssertTrue(report[5].hasSuffix(" | 0 | 0 | 0 | 0 | - | - | - | - | - | - | 0.0 | - | - | no | - | - | - | - | -"), report[5])
        for line in report[4...] {
            XCTAssertEqual(line.components(separatedBy: " | ").count, SensorTrace.columns.count)
        }
    }

    func testReportNamesTheSettings() {
        let report = SensorTrace().report(settings(interval: 10, sensor: "TCMb", alpha: nil, minimum: 20))
        XCTAssertEqual(report[1], "Polling interval: 10.0 s | hold: 1 ticks | current: 1 ticks | curve sensor: TCMb")
        XCTAssertEqual(report[2], "Smoothing: off | minimum fan: 20.0 % | curve: -")
    }

    func testExportMarksHeldSensorsAndAppendsTheTrace() {
        var stale = sensor("Tp02", 95, held: true)
        stale.isStale = true
        let sensors = [sensor("Tp00", 93, held: true), sensor("Tp01", 91), stale]
        let dump = SensorRegistry.exportDiagnosticData(sensors: sensors, fans: [], trace: ["=== CPU Sensor Trace ===", "a | b"])
        XCTAssertTrue(dump.contains("93.00°C | KNOWN | HELD\n"))
        XCTAssertTrue(dump.contains("95.00°C | KNOWN | HELD (stale)"))
        XCTAssertFalse(dump.contains("91.00°C | KNOWN | HELD"))
        XCTAssertTrue(dump.contains("=== CPU Sensor Trace ===\na | b\n\n=== Instructions ==="))
        XCTAssertTrue(dump.contains("Mystral: "))
    }

    @MainActor
    func testControllerRecordsATraceEntryPerTick() throws {
        let previousActiveProfile = UserDefaults.standard.object(forKey: "activeProfileId")
        let storageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let controller = FanController(smcService: MockSMCService(), profileManager: ProfileManager(storageDirectory: storageDirectory))
        defer {
            controller.stop()
            if let previousActiveProfile {
                UserDefaults.standard.set(previousActiveProfile, forKey: "activeProfileId")
            } else {
                UserDefaults.standard.removeObject(forKey: "activeProfileId")
            }
        }
        XCTAssertEqual(controller.sensorTraceReport().count, 4)
        controller.start()
        let report = controller.sensorTraceReport()
        XCTAssertEqual(report.count, 5)
        XCTAssertTrue(report[4].contains(" | 2 | 0 | 0 | 0 | Tp01…Tp09 | Tp01 | "), report[4])
        XCTAssertTrue(report[4].contains(" | 62.0 | no | 62.0 | "), report[4])
        XCTAssertEqual(report[4].components(separatedBy: " | ").count, SensorTrace.columns.count)
    }
}
