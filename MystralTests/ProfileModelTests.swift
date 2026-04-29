import XCTest
@testable import Mystral

final class ProfileModelTests: XCTestCase {
    func testCurvePointCodable() throws {
        let point = CurvePoint(temperature: 65.0, fanPercentage: 50.0)
        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(CurvePoint.self, from: data)
        XCTAssertEqual(decoded.temperature, 65.0)
        XCTAssertEqual(decoded.fanPercentage, 50.0)
    }

    func testProfileCodable() throws {
        let profile = Profile(
            name: "Test",
            icon: "fan",
            isPreset: false,
            curvePoints: [
                CurvePoint(temperature: 30, fanPercentage: 10),
                CurvePoint(temperature: 90, fanPercentage: 100)
            ],
            sensorKey: "Tp09"
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.curvePoints.count, 2)
        XCTAssertEqual(decoded.sensorKey, "Tp09")
        XCTAssertFalse(decoded.isPreset)
    }

    func testCurvePointsSortedByTemperature() {
        let points = [
            CurvePoint(temperature: 90, fanPercentage: 100),
            CurvePoint(temperature: 30, fanPercentage: 10),
            CurvePoint(temperature: 60, fanPercentage: 50)
        ]
        let sorted = points.sortedByTemperature()
        XCTAssertEqual(sorted[0].temperature, 30)
        XCTAssertEqual(sorted[1].temperature, 60)
        XCTAssertEqual(sorted[2].temperature, 90)
    }
}
