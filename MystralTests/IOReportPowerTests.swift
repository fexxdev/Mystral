import XCTest
@testable import Mystral

final class IOReportPowerTests: XCTestCase {
    func testNanojoules() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 1_000_000_000, unit: "nJ"), 1.0, accuracy: 1e-9)
    }

    func testMicrojoules() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 1_000_000, unit: "uJ"), 1.0, accuracy: 1e-9)
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 1_000, unit: "µJ"), 0.001, accuracy: 1e-9)
    }

    func testMillijoules() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 1_000, unit: "mJ"), 1.0, accuracy: 1e-9)
    }

    func testJoulesDefault() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 5, unit: "J"), 5.0, accuracy: 1e-9)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 2_000, unit: "MJ"), 2.0, accuracy: 1e-9)
    }
}
