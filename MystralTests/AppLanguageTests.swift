import XCTest
@testable import Mystral

final class AppLanguageTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MystralTests.AppLanguage.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func current() -> AppLanguage {
        AppLanguage.current(in: defaults, domain: suiteName)
    }

    private func store(_ languages: [String]) {
        defaults.set(languages, forKey: AppLanguage.defaultsKey)
    }

    func testNoOverrideMeansSystem() {
        XCTAssertEqual(current(), .system)
    }

    func testApplyStoresTheOverrideAndReadsItBack() {
        for language in AppLanguage.allCases where language != .system {
            language.apply(to: defaults)
            XCTAssertEqual(defaults.stringArray(forKey: AppLanguage.defaultsKey), [language.rawValue])
            XCTAssertEqual(current(), language)
        }
    }

    func testSystemRemovesTheOverride() {
        AppLanguage.italian.apply(to: defaults)
        AppLanguage.system.apply(to: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?[AppLanguage.defaultsKey])
        XCTAssertEqual(current(), .system)
    }

    /// System Settings → Language & Region → Applications may store a regional variant.
    func testRegionalVariantsMapToTheShippedLanguage() {
        store(["zh-Hans-CN"]); XCTAssertEqual(current(), .simplifiedChinese)
        store(["it-IT"]); XCTAssertEqual(current(), .italian)
        store(["en-GB"]); XCTAssertEqual(current(), .english)
    }

    func testUnshippedLanguagesShowAsSystem() {
        store(["fr"]); XCTAssertEqual(current(), .system)
        store(["zh-Hant"]); XCTAssertEqual(current(), .system)
        store(["itx"]); XCTAssertEqual(current(), .system)
    }

    /// The picker must offer exactly the languages the app bundle ships.
    func testPickerMatchesShippedLocalizations() {
        let shipped = Set(Bundle(for: ProfileManager.self).localizations).subtracting(["Base"])
        let offered = Set(AppLanguage.allCases.filter { $0 != .system }.map(\.rawValue))
        XCTAssertEqual(offered, shipped)
    }

    func testNativeNamesAreDistinct() {
        let names = AppLanguage.allCases.filter { $0 != .system }.map(\.nativeName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertFalse(names.contains(""))
    }
}
