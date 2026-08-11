import XCTest
@testable import Mystral

final class UpdateCheckerTests: XCTestCase {

    func testEqualVersions() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.0", "1.0.0"), .orderedSame)
    }

    func testNewerPatch() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.1", "1.0.0"), .orderedDescending)
    }

    func testNewerMinor() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.1.0", "1.0.9"), .orderedDescending)
    }

    func testNewerMajor() {
        XCTAssertEqual(UpdateChecker.compareVersions("2.0.0", "1.99.99"), .orderedDescending)
    }

    func testOlder() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.0", "1.0.1"), .orderedAscending)
    }

    func testDifferentLengths() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.0.1", "1.0.0"), .orderedDescending)
    }

    func testNonNumericIgnored() {
        XCTAssertEqual(UpdateChecker.compareVersions("1.0.0", "1.0.0-beta"), .orderedSame)
    }

    func testTrustedReleaseURLRequiresTheMystralGitHubRepository() {
        XCTAssertTrue(UpdateChecker.isTrustedReleaseURL(URL(string: "https://github.com/fexxdev/Mystral/releases/download/v1.1.2/Mystral-1.1.2.dmg")!))
        XCTAssertFalse(UpdateChecker.isTrustedReleaseURL(URL(string: "http://github.com/fexxdev/Mystral/releases/download/v1.1.2/Mystral-1.1.2.dmg")!))
        XCTAssertFalse(UpdateChecker.isTrustedReleaseURL(URL(string: "https://evil.example/Mystral-1.1.2.dmg")!))
        XCTAssertFalse(UpdateChecker.isTrustedReleaseURL(URL(string: "https://github.com/other/repo/releases/download/v1.1.2/Mystral-1.1.2.dmg")!))
    }

    func testDeveloperIDSignatureOutputRejectsAdHocSignatures() {
        XCTAssertFalse(UpdateChecker.hasDeveloperIDSignature("Signature=adhoc\n"))
        XCTAssertTrue(UpdateChecker.hasDeveloperIDSignature("Authority=Developer ID Application: Example (ABCDE12345)\nTeamIdentifier=ABCDE12345\n"))
    }

    func testBundleMetadataRequiresTheExpectedApplicationAndNewerVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let info: NSDictionary = [
            "CFBundleIdentifier": "com.fexxdev.Mystral",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.1.2"
        ]
        XCTAssertTrue(info.write(to: contents.appendingPathComponent("Info.plist"), atomically: true))
        XCTAssertTrue(UpdateChecker.isValidBundleMetadata(at: root.path, currentVersion: "1.1.1"))
    }
}
