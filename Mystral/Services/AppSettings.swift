import Foundation

enum AppSettings {
    static let resettableKeys = [
        "menuBarDisplayMode", "menuBarTempSource", "pollingInterval",
        "smoothingEnabled", "smoothingAlpha", "deadbandPercent",
        "minimumFanPercentage", "aggressiveOverrideEnabled",
        "alertsEnabled", "alertsHighTempThreshold", "alertsFanStuckEnabled",
        "autoSwitchEnabled", "updatesAutoCheckEnabled", "updatesLastCheckedAt"
    ]

    static func reset(_ defaults: UserDefaults = .standard) {
        for key in resettableKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
