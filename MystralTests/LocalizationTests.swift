import XCTest
@testable import Mystral

/// Checks the compiled string catalog, not the source file: a language missing from the
/// build, or a key that only resolves at runtime and fell out of the catalog, fails here.
final class LocalizationTests: XCTestCase {
    private let appBundle = Bundle(for: ProfileManager.self)

    private func localized(_ key: String, in language: String) -> String? {
        guard let path = appBundle.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func testAppShipsItalianAndSimplifiedChinese() {
        XCTAssertTrue(appBundle.localizations.contains("it"))
        XCTAssertTrue(appBundle.localizations.contains("zh-Hans"))
    }

    func testStaticKeysResolve() {
        XCTAssertEqual(localized("Settings", in: "zh-Hans"), "设置")
        XCTAssertEqual(localized("Settings", in: "it"), "Impostazioni")
    }

    /// Enum rawValues and preset names are looked up at runtime, so the compiler never
    /// sees them; the catalog keeps them as manual entries.
    func testRuntimeKeysResolve() {
        XCTAssertEqual(localized(SensorCategory.cpuPerformance.rawValue, in: "zh-Hans"), "CPU 性能核心")
        XCTAssertEqual(localized(MenuBarDisplayMode.iconOnly.rawValue, in: "zh-Hans"), "仅显示图标")
        XCTAssertEqual(localized(MenuBarTempSource.hottest.rawValue, in: "zh-Hans"), "最热传感器")
        XCTAssertEqual(localized(SidebarItem.profiles.rawValue, in: "zh-Hans"), "配置")
        XCTAssertEqual(localized("Balanced", in: "zh-Hans"), "均衡")
        XCTAssertEqual(localized("Balanced", in: "it"), "Bilanciato")
    }

    func testPositionalArgumentsKeepTheirOrder() throws {
        let format = try XCTUnwrap(localized("Temp %lld°C → %lld°C   |   Fan %lld → %lld RPM", in: "zh-Hans"))
        let text = String(format: format, 40, 80, 1200, 4500)
        XCTAssertEqual(text, "温度 40°C → 80°C   |   风扇 1200 → 4500 RPM")
    }

    func testCustomProfileNamesAreNotTranslated() {
        let custom = Profile(name: "Balanced", isPreset: false, curvePoints: [CurvePoint(temperature: 50, fanPercentage: 50)])
        XCTAssertEqual(custom.displayName, "Balanced")
    }

    func testThermalLevelsHaveDistinctNames() {
        let names = Set(ProfileTrigger.ThermalLevel.allCases.map(\.localizedName))
        XCTAssertEqual(names.count, ProfileTrigger.ThermalLevel.allCases.count)
    }
}
