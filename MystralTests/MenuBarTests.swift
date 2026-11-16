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

    private let posix = Locale(identifier: "en_US_POSIX")

    func testFormatTotalWatts() {
        XCTAssertEqual(MenuBarManager.formatTotalWatts(nil), "-- W")
        XCTAssertEqual(MenuBarManager.formatTotalWatts(0), "-- W")
        XCTAssertEqual(MenuBarManager.formatTotalWatts(38.4, locale: posix), "38 W")
        XCTAssertEqual(MenuBarManager.formatTotalWatts(44.6, locale: posix), "45 W")
        XCTAssertEqual(MenuBarManager.formatTotalWatts(7.26, locale: posix), "7.3 W")
    }

    func testFormatPowerBreakdown() {
        XCTAssertEqual(MenuBarManager.formatPowerBreakdown(cpu: 17.2, gpu: 4.1, locale: posix), "CPU 17 W  ·  GPU 4.1 W")
        XCTAssertEqual(MenuBarManager.formatPowerBreakdown(cpu: 17.0, gpu: nil, locale: posix), "CPU 17 W")
        XCTAssertEqual(MenuBarManager.formatPowerBreakdown(cpu: nil, gpu: 4.0, locale: posix), "GPU 4.0 W")
        XCTAssertNil(MenuBarManager.formatPowerBreakdown(cpu: nil, gpu: nil))
    }

    /// Idle readings measured on an M3 Pro: CPU about 1.4 W, GPU about 0.1 W.
    /// Whole-watt rounding showed them as "CPU 1 W · GPU 0 W".
    func testSubWattReadingsKeepADecimal() {
        XCTAssertEqual(MenuBarManager.formatPowerBreakdown(cpu: 1.42, gpu: 0.087, locale: posix), "CPU 1.4 W  ·  GPU 0.1 W")
        XCTAssertEqual(PowerMonitor.formatWatts(0.02, locale: posix), "0.0 W")
        XCTAssertEqual(PowerMonitor.formatWatts(9.94, locale: posix), "9.9 W")
        XCTAssertEqual(PowerMonitor.formatWatts(9.96, locale: posix), "10 W")
        XCTAssertEqual(PowerMonitor.formatWatts(1.4, locale: Locale(identifier: "it_IT")), "1,4 W")
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
