import XCTest
@testable import Mystral

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
}
