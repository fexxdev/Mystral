import XCTest
@testable import Mystral

@MainActor
final class AlertManagerTests: XCTestCase {

    private func makeManager() -> AlertManager {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "alertsEnabled")
        defaults.removeObject(forKey: "alertsHighTempThreshold")
        defaults.removeObject(forKey: "alertsFanStuckEnabled")
        return AlertManager()
    }

    func testDefaultThresholds() {
        let m = makeManager()
        XCTAssertTrue(m.enabled)
        XCTAssertTrue(m.fanStuckEnabled)
        XCTAssertEqual(m.highTempThreshold, 95)
    }

    func testEnabledFlagPersists() {
        let m = makeManager()
        m.enabled = false
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "alertsEnabled"), false)
        m.highTempThreshold = 80
        XCTAssertEqual(UserDefaults.standard.double(forKey: "alertsHighTempThreshold"), 80)
    }

    // The evaluate() side effect (sending notifications) is hard to assert without
    // a UNUserNotificationCenter test double, but we can at least exercise the code path
    // to ensure it doesn't crash with empty/edge-case inputs.

    func testEvaluateWithEmptyInputsDoesNotCrash() {
        let m = makeManager()
        m.evaluate(sensors: [], fans: [], expectedFanPercent: [:])
    }

    func testEvaluateBelowThresholdDoesNothing() {
        let m = makeManager()
        m.highTempThreshold = 95
        let cool = Sensor(id: "Tp01", name: "CPU 1", temperature: 60)
        m.evaluate(sensors: [cool], fans: [], expectedFanPercent: [:])
    }
}
