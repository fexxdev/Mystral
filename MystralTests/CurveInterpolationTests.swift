import XCTest
@testable import Mystral

@MainActor
final class CurveInterpolationTests: XCTestCase {
    let curve: [CurvePoint] = [
        CurvePoint(temperature: 30, fanPercentage: 10),
        CurvePoint(temperature: 50, fanPercentage: 30),
        CurvePoint(temperature: 70, fanPercentage: 60),
        CurvePoint(temperature: 90, fanPercentage: 100)
    ]

    func testExactPoint() { XCTAssertEqual(FanController.interpolate(temperature: 50, curve: curve), 30, accuracy: 0.01) }
    func testMidpoint() { XCTAssertEqual(FanController.interpolate(temperature: 40, curve: curve), 20, accuracy: 0.01) }
    func testBelowMinimum() { XCTAssertEqual(FanController.interpolate(temperature: 10, curve: curve), 10, accuracy: 0.01) }
    func testAboveMaximum() { XCTAssertEqual(FanController.interpolate(temperature: 100, curve: curve), 100, accuracy: 0.01) }
    func testQuarterPoint() { XCTAssertEqual(FanController.interpolate(temperature: 55, curve: curve), 37.5, accuracy: 0.01) }
    func testSinglePoint() { XCTAssertEqual(FanController.interpolate(temperature: 50, curve: [CurvePoint(temperature: 0, fanPercentage: 100)]), 100, accuracy: 0.01) }
    func testEmptyCurve() { XCTAssertEqual(FanController.interpolate(temperature: 50, curve: []), 0, accuracy: 0.01) }
    func testUnsortedCurve() {
        let unsorted = [CurvePoint(temperature: 70, fanPercentage: 60), CurvePoint(temperature: 30, fanPercentage: 10),
                        CurvePoint(temperature: 90, fanPercentage: 100), CurvePoint(temperature: 50, fanPercentage: 30)]
        XCTAssertEqual(FanController.interpolate(temperature: 40, curve: unsorted), 20, accuracy: 0.01)
    }

    // MARK: - Heartbeat

    /// The helper hands the fans back to macOS when it hears nothing for
    /// `heartbeatTimeout`, and it only looks every `tickInterval`. Whatever polling
    /// interval the user picks, a heartbeat must land inside that window. At 10 s
    /// polling the per-tick heartbeat did not, and the fans ran on automatic control.
    func testHeartbeatAlwaysBeatsTheHelperTimeout() {
        for polling in [2.0, 5.0, 10.0] {
            let gap = FanController.heartbeatPeriod(forPollingInterval: polling) ?? polling
            XCTAssertLessThan(gap + SMCHelperMode.tickInterval, SMCHelperMode.heartbeatTimeout,
                              "polling every \(polling) s leaves the helper without a heartbeat for too long")
        }
    }

    func testFastPollingNeedsNoSeparateHeartbeat() {
        XCTAssertNil(FanController.heartbeatPeriod(forPollingInterval: 2))
        XCTAssertEqual(FanController.heartbeatPeriod(forPollingInterval: 5), FanController.heartbeatInterval)
        XCTAssertEqual(FanController.heartbeatPeriod(forPollingInterval: 10), FanController.heartbeatInterval)
    }
}
