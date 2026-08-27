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

    @MainActor
    func testThermalNotificationFromBackgroundEvaluatesOnMainActor() async throws {
        let previousEnabled = UserDefaults.standard.object(forKey: "autoSwitchEnabled")
        let previousActiveProfile = UserDefaults.standard.object(forKey: "activeProfileId")
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let manager = ProfileManager(storageDirectory: storageDirectory)
        let switcher = ProfileAutoSwitcher(profileManager: manager)
        defer {
            switcher.stop()
            if let previousEnabled {
                UserDefaults.standard.set(previousEnabled, forKey: "autoSwitchEnabled")
            } else {
                UserDefaults.standard.removeObject(forKey: "autoSwitchEnabled")
            }
            if let previousActiveProfile {
                UserDefaults.standard.set(previousActiveProfile, forKey: "activeProfileId")
            } else {
                UserDefaults.standard.removeObject(forKey: "activeProfileId")
            }
        }

        switcher.enabled = true
        switcher.start()
        let profile = Profile(
            name: "Thermal notification test",
            curvePoints: [CurvePoint(temperature: 50, fanPercentage: 50)],
            triggers: ProfileTrigger.ThermalLevel.allCases.map { .thermalState($0) }
        )
        try manager.saveCustomProfile(profile)

        let notificationPosted = expectation(description: "thermal notification posted")
        DispatchQueue.global(qos: .userInitiated).async {
            NotificationCenter.default.post(
                name: ProcessInfo.thermalStateDidChangeNotification,
                object: nil
            )
            notificationPosted.fulfill()
        }
        await fulfillment(of: [notificationPosted], timeout: 1)

        for _ in 0..<100 {
            if manager.activeProfileId == profile.id { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(manager.activeProfileId, profile.id)
    }

    @MainActor
    func testScreenWakeNotificationFromBackgroundDoesNotCrash() async throws {
        let previousActiveProfile = UserDefaults.standard.object(forKey: "activeProfileId")
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let manager = ProfileManager(storageDirectory: storageDirectory)
        let controller = FanController(smcService: MockSMCService(), profileManager: manager)
        defer {
            controller.stop()
            if let previousActiveProfile {
                UserDefaults.standard.set(previousActiveProfile, forKey: "activeProfileId")
            } else {
                UserDefaults.standard.removeObject(forKey: "activeProfileId")
            }
        }

        let notificationPosted = expectation(description: "screen wake notification posted")
        DispatchQueue.global(qos: .userInitiated).async {
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.screensDidWakeNotification,
                object: nil
            )
            notificationPosted.fulfill()
        }
        await fulfillment(of: [notificationPosted], timeout: 1)
        try await Task.sleep(for: .milliseconds(20))
    }
}
