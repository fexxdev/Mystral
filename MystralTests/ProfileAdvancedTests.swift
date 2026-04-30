import XCTest
@testable import Mystral

final class ProfileAdvancedTests: XCTestCase {

    func testProfileWithPerFanCurvesRoundTrip() throws {
        let shared = [
            CurvePoint(temperature: 30, fanPercentage: 20),
            CurvePoint(temperature: 80, fanPercentage: 90)
        ]
        let fanCurve = [
            CurvePoint(temperature: 30, fanPercentage: 35),
            CurvePoint(temperature: 80, fanPercentage: 100)
        ]
        let profile = Profile(
            name: "Mixed",
            curvePoints: shared,
            sensorKey: "Tp01",
            fanCurves: [1: fanCurve]
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)

        XCTAssertEqual(decoded.fanCurves?[1]?.count, 2)
        XCTAssertEqual(decoded.fanCurves?[1]?[0].fanPercentage, 35)
        XCTAssertNil(decoded.fanCurves?[0])
    }

    func testCurveForFanFallsBackToShared() {
        let shared = [CurvePoint(temperature: 50, fanPercentage: 50)]
        let override = [CurvePoint(temperature: 50, fanPercentage: 100)]
        let profile = Profile(name: "X", curvePoints: shared, fanCurves: [0: override])

        XCTAssertEqual(profile.curve(for: 0).first?.fanPercentage, 100)
        XCTAssertEqual(profile.curve(for: 1).first?.fanPercentage, 50)
        XCTAssertTrue(profile.hasOverride(for: 0))
        XCTAssertFalse(profile.hasOverride(for: 1))
    }

    func testTriggerCodableRoundTrip() throws {
        let triggers: [ProfileTrigger] = [
            .powerSource(.battery),
            .thermalState(.serious),
            .frontmostApp(bundleId: "com.apple.Xcode")
        ]
        let profile = Profile(name: "Auto", curvePoints: [
            CurvePoint(temperature: 30, fanPercentage: 10),
            CurvePoint(temperature: 90, fanPercentage: 100)
        ], triggers: triggers)

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)

        XCTAssertEqual(decoded.triggers?.count, 3)
        XCTAssertEqual(decoded.triggers?[0], .powerSource(.battery))
        XCTAssertEqual(decoded.triggers?[1], .thermalState(.serious))
        XCTAssertEqual(decoded.triggers?[2], .frontmostApp(bundleId: "com.apple.Xcode"))
    }

    func testLegacyProfileWithoutNewFieldsDecodes() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Old","icon":"fan","isPreset":false,
         "curvePoints":[{"temperature":40,"fanPercentage":25}]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Profile.self, from: json)
        XCTAssertEqual(decoded.name, "Old")
        XCTAssertEqual(decoded.sensorKey, "")
        XCTAssertNil(decoded.fanCurves)
        XCTAssertNil(decoded.triggers)
    }

    func testFanCurvesSerializedAsStringKeyedDict() throws {
        let profile = Profile(
            name: "X",
            curvePoints: [CurvePoint(temperature: 30, fanPercentage: 10)],
            fanCurves: [0: [CurvePoint(temperature: 50, fanPercentage: 50)]]
        )
        let data = try JSONEncoder().encode(profile)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fanCurves = try XCTUnwrap(json["fanCurves"] as? [String: Any])
        XCTAssertNotNil(fanCurves["0"])
    }
}
