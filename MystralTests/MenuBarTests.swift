import XCTest
@testable import Mystral

final class MenuBarTests: XCTestCase {

    // MARK: - MenuBarDisplayMode

    func testAllCasesCount() {
        XCTAssertEqual(MenuBarDisplayMode.allCases.count, 7)
    }

    func testShowsIconForIconModes() {
        XCTAssertTrue(MenuBarDisplayMode.iconOnly.showsIcon)
        XCTAssertTrue(MenuBarDisplayMode.iconAndTemperature.showsIcon)
        XCTAssertTrue(MenuBarDisplayMode.iconAndRPM.showsIcon)
        XCTAssertTrue(MenuBarDisplayMode.iconAndProfile.showsIcon)
    }

    func testHidesIconForTextOnlyModes() {
        XCTAssertFalse(MenuBarDisplayMode.temperatureOnly.showsIcon)
        XCTAssertFalse(MenuBarDisplayMode.rpmOnly.showsIcon)
        XCTAssertFalse(MenuBarDisplayMode.miniGraph.showsIcon)
    }

    func testDisplayModeRawValueRoundTrip() {
        for mode in MenuBarDisplayMode.allCases {
            XCTAssertEqual(MenuBarDisplayMode(rawValue: mode.rawValue), mode)
        }
    }

    func testDisplayModeCodableRoundTrip() throws {
        for mode in MenuBarDisplayMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(MenuBarDisplayMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testInvalidRawValueReturnsNil() {
        XCTAssertNil(MenuBarDisplayMode(rawValue: "Nonexistent"))
    }

    // MARK: - MenuBarTempSource

    func testTempSourceAllCasesCount() {
        XCTAssertEqual(MenuBarTempSource.allCases.count, 5)
    }

    func testTempSourceRawValueRoundTrip() {
        for source in MenuBarTempSource.allCases {
            XCTAssertEqual(MenuBarTempSource(rawValue: source.rawValue), source)
        }
    }

    func testTempSourceCodableRoundTrip() throws {
        for source in MenuBarTempSource.allCases {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(MenuBarTempSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
    }
}
