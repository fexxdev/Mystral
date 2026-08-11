import XCTest
@testable import Mystral

final class MockSMCService: SMCServiceProtocol, @unchecked Sendable {
    var sensors: [Sensor] = [
        Sensor(id: "Tp09", name: "CPU Efficiency Core 1", temperature: 45.0),
        Sensor(id: "Tp01", name: "CPU Performance Core 1", temperature: 62.0)
    ]
    var fans: [Fan] = [
        Fan(id: 0, name: "Left Fan", currentRPM: 1200, targetRPM: 1200, minRPM: 1000, maxRPM: 5500, mode: .auto),
        Fan(id: 1, name: "Right Fan", currentRPM: 1200, targetRPM: 1200, minRPM: 1000, maxRPM: 5500, mode: .auto)
    ]
    var lastSetFanIndex: Int?
    var lastSetPercentage: Double?
    var lastSetMode: FanMode?
    var lastForcedModeFanCount: Int?
    var lastForcedModeForced: Bool?

    func getAllSensors() throws -> [Sensor] { sensors }
    func readTemperature(key: String) throws -> Double { sensors.first { $0.id == key }?.temperature ?? 0 }
    func getAllFans() throws -> [Fan] { fans }
    func readFanSpeed(index: Int) throws -> Int { fans[index].currentRPM }
    func setFanSpeed(index: Int, percentage: Double) throws { lastSetFanIndex = index; lastSetPercentage = percentage }
    func setFanMode(index: Int, mode: FanMode) throws { lastSetMode = mode }
    func setForcedMode(fanCount: Int, forced: Bool) throws { lastForcedModeFanCount = fanCount; lastForcedModeForced = forced }
    func heartbeat() throws {}
}

final class SMCServiceTests: XCTestCase {
    func testMockReturnsSensors() throws {
        let svc = MockSMCService()
        let sensors = try svc.getAllSensors()
        XCTAssertEqual(sensors.count, 2)
        XCTAssertEqual(sensors[0].id, "Tp09")
    }
    func testMockReturnsFans() throws {
        let svc = MockSMCService()
        let fans = try svc.getAllFans()
        XCTAssertEqual(fans.count, 2)
        XCTAssertEqual(fans[0].maxRPM, 5500)
    }
    func testMockSetFanSpeed() throws {
        let svc = MockSMCService()
        try svc.setFanSpeed(index: 0, percentage: 75.0)
        XCTAssertEqual(svc.lastSetFanIndex, 0)
        XCTAssertEqual(svc.lastSetPercentage, 75.0)
    }

    // Issue #2: on system sleep the helper must hand fan control back to macOS
    // auto mode so the firmware idles the fans (no whining during sleep).
    func testRestoreAutoModeReleasesForcedControl() {
        let svc = MockSMCService()
        SMCHelperMode.restoreAutoMode(smc: svc)
        XCTAssertEqual(svc.lastForcedModeForced, false)
        XCTAssertEqual(svc.lastForcedModeFanCount, 2) // mock reports 2 fans
    }

    // Issue #2: the exact routing the IOKit sleep/wake callback runs, driven with the
    // real IOKit ABI message numbers from <IOKit/IOMessage.h>. handlePowerMessage
    // returns whether the message must be acked via IOAllowPowerChange.

    func testSystemWillSleepHandsFansBackToAuto() {
        let svc = MockSMCService()
        let needsAck = SMCHelperMode.handlePowerMessage(0xE000_0280, smc: svc) // kIOMessageSystemWillSleep
        XCTAssertEqual(svc.lastForcedModeForced, false)
        XCTAssertEqual(svc.lastForcedModeFanCount, 2)
        XCTAssertTrue(needsAck) // must ack or the system stalls ~30s before sleeping
    }

    func testCanSystemSleepIsAckedWithoutTouchingFans() {
        let svc = MockSMCService()
        let needsAck = SMCHelperMode.handlePowerMessage(0xE000_0270, smc: svc) // kIOMessageCanSystemSleep
        XCTAssertNil(svc.lastForcedModeForced) // fans left untouched
        XCTAssertTrue(needsAck)
    }

    func testPoweredOnLeavesFansToTheAppAndNeedsNoAck() {
        let svc = MockSMCService()
        let needsAck = SMCHelperMode.handlePowerMessage(0xE000_0300, smc: svc) // kIOMessageSystemHasPoweredOn
        XCTAssertNil(svc.lastForcedModeForced) // app's handleWake re-applies the curve
        XCTAssertFalse(needsAck)
    }

    func testIPCUsesPrivateApplicationSupportDirectory() {
        XCTAssertFalse(SMCIPC.directoryPath.hasPrefix("/tmp/"))
        XCTAssertTrue(SMCIPC.directoryPath.contains("Application Support/Mystral/ipc"))
        XCTAssertTrue(SMCHelperMode.dataPath.hasPrefix(SMCIPC.directoryPath))
        XCTAssertTrue(SMCHelperMode.cmdDir.hasPrefix(SMCIPC.directoryPath))
    }

    func testIPCRejectsWorldReadableAndSymlinkedDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MystralIPCTests-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("ipc", isDirectory: true)
        let link = root.appendingPathComponent("link", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertTrue(chmod(directory.path, 0o700) == 0)
        XCTAssertTrue(SMCIPC.isSecureDirectory(path: directory.path, expectedOwnerUID: getuid()))

        XCTAssertTrue(chmod(directory.path, 0o755) == 0)
        XCTAssertFalse(SMCIPC.isSecureDirectory(path: directory.path, expectedOwnerUID: getuid()))

        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        XCTAssertFalse(SMCIPC.isSecureDirectory(path: link.path, expectedOwnerUID: getuid()))
    }

    func testHeartbeatTimeoutRequiresAnActiveSession() {
        let now = Date()
        XCTAssertFalse(SMCHelperMode.shouldRestoreForHeartbeat(lastHeartbeat: nil, now: now, timeout: 8))
        XCTAssertFalse(SMCHelperMode.shouldRestoreForHeartbeat(lastHeartbeat: now.addingTimeInterval(-7), now: now, timeout: 8))
        XCTAssertTrue(SMCHelperMode.shouldRestoreForHeartbeat(lastHeartbeat: now.addingTimeInterval(-9), now: now, timeout: 8))
    }

    func testCommandValidationRejectsOutOfRangeAndUnknownActions() {
        XCTAssertTrue(SMCHelperMode.Command(action: "heartbeat", index: 0, value: nil).isValid)
        XCTAssertTrue(SMCHelperMode.Command(action: "setFanSpeed", index: 0, value: 50).isValid)
        XCTAssertFalse(SMCHelperMode.Command(action: "setFanSpeed", index: -1, value: 50).isValid)
        XCTAssertFalse(SMCHelperMode.Command(action: "setFanSpeed", index: 0, value: 101).isValid)
        XCTAssertFalse(SMCHelperMode.Command(action: "run-shell", index: 0, value: nil).isValid)
    }

    func testHelperInstallationRejectsUserWritableExecutablePath() {
        XCTAssertFalse(HelperDaemon.isAllowedExecutablePath("/Users/test/Mystral.app/Contents/MacOS/Mystral"))
    }

    func testHelperInstallationAllowsStandardUserOwnedApplicationsInstall() {
        XCTAssertTrue(HelperDaemon.isAllowedExecutableMetadata(
            appOwnerUID: getuid(),
            executableOwnerUID: getuid(),
            currentUID: getuid(),
            appPermissions: 0o755,
            executablePermissions: 0o755
        ))
        XCTAssertFalse(HelperDaemon.isAllowedExecutableMetadata(
            appOwnerUID: getuid() + 1,
            executableOwnerUID: getuid() + 1,
            currentUID: getuid(),
            appPermissions: 0o755,
            executablePermissions: 0o755
        ))
        XCTAssertFalse(HelperDaemon.isAllowedExecutableMetadata(
            appOwnerUID: getuid(),
            executableOwnerUID: getuid(),
            currentUID: getuid(),
            appPermissions: 0o775,
            executablePermissions: 0o755
        ))
    }

    func testHelperInstallationAcceptsInstalledApplicationsBundle() throws {
        let executablePath = "/Applications/Mystral.app/Contents/MacOS/Mystral"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: executablePath))
        XCTAssertTrue(HelperDaemon.isAllowedExecutablePath(executablePath))
    }

    func testHelperInstallationUsesDedicatedPrivilegedTool() {
        XCTAssertEqual(
            HelperDaemon.helperToolPath,
            "/Library/PrivilegedHelperTools/com.fexxdev.Mystral.helper"
        )
    }

    func testHelperInstallationBootstrapsBeforeEnablingLaunchdJob() {
        let commands = HelperDaemon.launchdLifecycleCommands(plistPath: "/tmp/mystral-helper.plist")
        let bootstrap = try! XCTUnwrap(commands.firstIndex { $0.contains(" bootstrap ") })
        let enable = try! XCTUnwrap(commands.firstIndex { $0.contains(" enable ") })
        let kickstart = try! XCTUnwrap(commands.firstIndex { $0.contains(" kickstart ") })

        XCTAssertLessThan(bootstrap, enable)
        XCTAssertLessThan(enable, kickstart)
    }

    func testHelperInstallationUsesExistingTestExecutablePath() {
        XCTAssertEqual(HelperDaemon.installationFileCheckCommand, "/bin/test")
    }
}
