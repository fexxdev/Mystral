import XCTest
@testable import Mystral

final class SettingsDefaultsTests: XCTestCase {
    func testResetRemovesEveryPersistedSetting() {
        let suiteName = "MystralTests.SettingsDefaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keys = [
            "menuBarDisplayMode", "menuBarTempSource", "pollingInterval",
            "smoothingEnabled", "smoothingAlpha", "deadbandPercent",
            "minimumFanPercentage", "aggressiveOverrideEnabled",
            "alertsEnabled", "alertsHighTempThreshold", "alertsFanStuckEnabled",
            "autoSwitchEnabled", "updatesAutoCheckEnabled", "updatesLastCheckedAt"
        ]
        for key in keys { defaults.set("stored", forKey: key) }

        AppSettings.reset(defaults)

        for key in keys { XCTAssertNil(defaults.object(forKey: key), "Key was not reset: \(key)") }
    }
}
