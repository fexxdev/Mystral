import XCTest
@testable import Mystral

final class ProfileManagerTests: XCTestCase {
    var tempDir: URL!
    var manager: ProfileManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = ProfileManager(storageDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testPresetsAreLoaded() { XCTAssertEqual(manager.presets.count, 4); XCTAssertTrue(manager.presets.allSatisfy(\.isPreset)) }
    func testPresetNames() {
        let names = Set(manager.presets.map(\.name))
        XCTAssertTrue(names.contains("Silent")); XCTAssertTrue(names.contains("Balanced"))
        XCTAssertTrue(names.contains("Performance")); XCTAssertTrue(names.contains("Full Blast"))
    }
    func testAddCustomProfile() throws {
        let p = Profile(name: "My Profile", curvePoints: [CurvePoint(temperature: 30, fanPercentage: 20), CurvePoint(temperature: 80, fanPercentage: 90)])
        try manager.saveCustomProfile(p)
        XCTAssertEqual(manager.customProfiles.count, 1)
        XCTAssertEqual(manager.customProfiles[0].name, "My Profile")
    }
    func testCustomProfilePersistence() throws {
        let p = Profile(name: "Persisted", curvePoints: [CurvePoint(temperature: 50, fanPercentage: 50)])
        try manager.saveCustomProfile(p)
        let newManager = ProfileManager(storageDirectory: tempDir)
        XCTAssertEqual(newManager.customProfiles.count, 1)
        XCTAssertEqual(newManager.customProfiles[0].name, "Persisted")
    }
    func testDeleteCustomProfile() throws {
        let p = Profile(name: "ToDelete", curvePoints: [CurvePoint(temperature: 50, fanPercentage: 50)])
        try manager.saveCustomProfile(p)
        try manager.deleteCustomProfile(id: p.id)
        XCTAssertEqual(manager.customProfiles.count, 0)
    }
    func testDuplicatePreset() throws {
        let preset = manager.presets[0]
        let dup = try manager.duplicateAsCustom(preset)
        XCTAssertFalse(dup.isPreset)
        XCTAssertEqual(dup.curvePoints.count, preset.curvePoints.count)
        XCTAssertTrue(dup.name.contains(preset.name))
        XCTAssertEqual(manager.customProfiles.count, 1)
    }
    func testMaxCustomProfiles() throws {
        for i in 0..<10 {
            try manager.saveCustomProfile(Profile(name: "P\(i)", curvePoints: [CurvePoint(temperature: 50, fanPercentage: 50)]))
        }
        XCTAssertEqual(manager.customProfiles.count, 10)
        XCTAssertThrowsError(try manager.saveCustomProfile(Profile(name: "Extra", curvePoints: [CurvePoint(temperature: 50, fanPercentage: 50)])))
    }
}
