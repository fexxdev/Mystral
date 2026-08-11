import XCTest
@testable import Mystral

final class MystralTests: XCTestCase {
    func testResettableSettingsHaveAStableExplicitSet() {
        XCTAssertEqual(
            Set(AppSettings.resettableKeys),
            Set([
                "menuBarDisplayMode", "menuBarTempSource", "pollingInterval",
                "smoothingEnabled", "smoothingAlpha", "deadbandPercent",
                "minimumFanPercentage", "aggressiveOverrideEnabled",
                "alertsEnabled", "alertsHighTempThreshold", "alertsFanStuckEnabled",
                "autoSwitchEnabled", "updatesAutoCheckEnabled", "updatesLastCheckedAt"
            ])
        )
    }
}
