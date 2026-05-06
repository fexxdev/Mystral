import XCTest
@testable import Mystral

final class FanModelTests: XCTestCase {

    func testPercentageAtMin() {
        let fan = Fan(id: 0, name: "Fan", currentRPM: 1000, targetRPM: 1000, minRPM: 1000, maxRPM: 6000, mode: .auto)
        XCTAssertEqual(fan.percentage, 0, accuracy: 0.01)
    }

    func testPercentageAtMax() {
        let fan = Fan(id: 0, name: "Fan", currentRPM: 6000, targetRPM: 6000, minRPM: 1000, maxRPM: 6000, mode: .auto)
        XCTAssertEqual(fan.percentage, 100, accuracy: 0.01)
    }

    func testPercentageMidpoint() {
        let fan = Fan(id: 0, name: "Fan", currentRPM: 3500, targetRPM: 3500, minRPM: 1000, maxRPM: 6000, mode: .auto)
        XCTAssertEqual(fan.percentage, 50, accuracy: 0.01)
    }

    func testPercentageBelowMinClampsToZero() {
        let fan = Fan(id: 0, name: "Fan", currentRPM: 500, targetRPM: 500, minRPM: 1000, maxRPM: 6000, mode: .auto)
        XCTAssertEqual(fan.percentage, 0, accuracy: 0.01)
    }

    func testPercentageAboveMaxClampsTo100() {
        let fan = Fan(id: 0, name: "Fan", currentRPM: 7000, targetRPM: 7000, minRPM: 1000, maxRPM: 6000, mode: .auto)
        XCTAssertEqual(fan.percentage, 100, accuracy: 0.01)
    }

    func testPercentageEqualMinMax() {
        let fan = Fan(id: 0, name: "Fan", currentRPM: 3000, targetRPM: 3000, minRPM: 3000, maxRPM: 3000, mode: .auto)
        XCTAssertEqual(fan.percentage, 0, accuracy: 0.01)
    }

    func testFanModeRawValues() {
        XCTAssertEqual(FanMode.auto.rawValue, 0)
        XCTAssertEqual(FanMode.forced.rawValue, 1)
    }

    func testFanIdentifiable() {
        let fan = Fan(id: 42, name: "Test", currentRPM: 0, targetRPM: 0, minRPM: 0, maxRPM: 0, mode: .auto)
        XCTAssertEqual(fan.id, 42)
    }
}
