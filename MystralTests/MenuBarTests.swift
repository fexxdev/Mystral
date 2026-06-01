import XCTest
@testable import Mystral

final class MenuBarTests: XCTestCase {

    // MARK: - MenuBarDisplayMode

    func testAllCasesCount() {
        XCTAssertEqual(MenuBarDisplayMode.allCases.count, 9)
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

    func testShowsIconForPowerModes() {
        XCTAssertTrue(MenuBarDisplayMode.iconAndPower.showsIcon)
        XCTAssertFalse(MenuBarDisplayMode.powerOnly.showsIcon)
    }

    // MARK: - Power formatters

    func testFormatTotalWatts() {
        XCTAssertEqual(MenuBarManager.formatTotalWatts(nil), "-- W")
        XCTAssertEqual(MenuBarManager.formatTotalWatts(0), "-- W")
        XCTAssertEqual(MenuBarManager.formatTotalWatts(38.4), "38 W")
        XCTAssertEqual(MenuBarManager.formatTotalWatts(44.6), "45 W")
    }

    func testFormatPowerBreakdown() {
        XCTAssertEqual(MenuBarManager.formatPowerBreakdown(cpu: 17.2, gpu: 4.1), "CPU 17 W  ·  GPU 4 W")
        XCTAssertEqual(MenuBarManager.formatPowerBreakdown(cpu: 17.0, gpu: nil), "CPU 17 W")
        XCTAssertEqual(MenuBarManager.formatPowerBreakdown(cpu: nil, gpu: 4.0), "GPU 4 W")
        XCTAssertNil(MenuBarManager.formatPowerBreakdown(cpu: nil, gpu: nil))
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
