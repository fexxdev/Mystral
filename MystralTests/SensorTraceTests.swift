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
        let shown = [sensor("TCMz", 72.5), sensor("Te04", 71), sensor("Te05", 72.5),
                     sensor("Tp00", 93, held: true), sensor("Tp01", 91, held: true)]
        let entry = SensorTrace.entry(raw: raw, shown: shown, curveInput: 90.4, fans: [fan(2300)])

        XCTAssertEqual(entry.live, 2)
        XCTAssertEqual(entry.parked, 1)
        XCTAssertEqual(entry.held, 2)
        XCTAssertEqual(entry.firstLiveKey, "Te04")
        XCTAssertEqual(entry.lastLiveKey, "Te05")
        XCTAssertEqual(entry.liveMaximum, 72.5)
        XCTAssertEqual(entry.dieMaximum, 72.5)
        XCTAssertEqual(entry.defaultDriving, 93)
        XCTAssertEqual(entry.curveInput, 90.4)
        XCTAssertEqual(entry.fanRPM, [2300])
    }

    func testEntryWithoutCpuKeysHasNoLiveValues() {
        let entry = SensorTrace.entry(raw: [sensor("TB0T", 30)], shown: [sensor("TB0T", 30)], curveInput: nil, fans: [])
        XCTAssertEqual(entry.live, 0)
        XCTAssertNil(entry.firstLiveKey)
        XCTAssertNil(entry.liveMaximum)
        XCTAssertNil(entry.dieMaximum)
    }

    func testTraceKeepsTheNewestEntries() {
        var trace = SensorTrace()
        for i in 0..<(SensorTrace.capacity + 20) {
            trace.record(SensorTrace.entry(raw: [], shown: [], curveInput: Double(i), fans: []))
        }
        XCTAssertEqual(trace.entries.count, SensorTrace.capacity)
        XCTAssertEqual(trace.entries.first?.curveInput, 20)
        XCTAssertEqual(trace.entries.last?.curveInput, Double(SensorTrace.capacity + 19))
    }

    func testReportHasOneLinePerTick() {
        var trace = SensorTrace()
        let raw = [sensor("TCMz", 93.1), sensor("Te04", 70), sensor("Tp0w", 93.1), sensor("Tp1i", 40.0)]
        trace.record(SensorTrace.entry(raw: raw, shown: raw, curveInput: 91.84, fans: [fan(2310), fan(2290)]))
        trace.record(SensorTrace.entry(raw: [], shown: [], curveInput: nil, fans: []))

        let report = trace.report(pollingInterval: 2, curveSensor: "")
        XCTAssertEqual(report.count, 5)
        XCTAssertEqual(report[0], "=== CPU Sensor Trace (2 ticks, oldest first) ===")
        XCTAssertEqual(report[1], "Polling interval: 2.0 s | hold: 5 ticks | curve sensor: default (hottest CPU point)")
        XCTAssertTrue(report[3].hasSuffix(" | 2 | 1 | 0 | Te04…Tp0w | 93.1 | 93.1 | 93.1 | 91.8 | 2310/2290"), report[3])
        XCTAssertTrue(report[4].hasSuffix(" | 0 | 0 | 0 | - | - | - | 0.0 | - | -"), report[4])
        XCTAssertEqual(report[3].components(separatedBy: " | ").count, report[2].components(separatedBy: " | ").count)
    }

    func testReportNamesTheProfileSensor() {
        let report = SensorTrace().report(pollingInterval: 10, curveSensor: "TCMb")
        XCTAssertEqual(report[1], "Polling interval: 10.0 s | hold: 1 ticks | curve sensor: TCMb")
    }

    func testExportMarksHeldSensorsAndAppendsTheTrace() {
        let sensors = [sensor("Tp00", 93, held: true), sensor("Tp01", 91)]
        let dump = SensorRegistry.exportDiagnosticData(sensors: sensors, fans: [], trace: ["=== CPU Sensor Trace ===", "a | b"])
        XCTAssertTrue(dump.contains("93.00°C | KNOWN | HELD"))
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
        XCTAssertEqual(controller.sensorTraceReport().count, 3)
        controller.start()
        let report = controller.sensorTraceReport()
        XCTAssertEqual(report.count, 4)
        XCTAssertTrue(report[3].contains(" | 2 | 0 | 0 | Tp01…Tp09 | "), report[3])
        XCTAssertTrue(report[3].hasSuffix(" | 1200/1200"), report[3])
    }
}
