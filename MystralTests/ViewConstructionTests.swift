import SwiftUI
import XCTest
@testable import Mystral

@MainActor
final class ViewConstructionTests: XCTestCase {
    func testMainAndProfilesSidebarsUseStableWidths() {
        XCTAssertEqual(MainView.sidebarWidth, 200)
        XCTAssertEqual(ProfilesView.sidebarWidth, 260)
    }

    func testMainViewsBuildWithControllerData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MystralViewTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let profileManager = ProfileManager(storageDirectory: directory)
        let controller = FanController(smcService: MockSMCService(), profileManager: profileManager)
        controller.start()
        defer { controller.stop() }

        _ = MainView(
            fanController: controller,
            profileManager: profileManager,
            alertManager: nil,
            autoSwitcher: nil,
            updateChecker: nil
        ).body
        _ = DashboardView(fanController: controller, profileManager: profileManager).body
        _ = SensorsView(fanController: controller).body
        _ = FansView(fanController: controller).body
        _ = ProfilesView(fanController: controller, profileManager: profileManager).body
        _ = SettingsView(
            fanController: controller,
            profileManager: profileManager,
            alertManager: nil,
            autoSwitcher: nil,
            updateChecker: nil
        ).body

        let profile = try XCTUnwrap(profileManager.activeProfile)
        _ = CurveEditorView(
            profile: .constant(profile),
            sensorKeys: controller.sensors.map(\.id),
            fans: controller.fans
        ).body
        _ = SparklineView(data: [45, 50, 55]).body
        _ = SparklineView(data: [45]).body
    }
}
