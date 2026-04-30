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
}
