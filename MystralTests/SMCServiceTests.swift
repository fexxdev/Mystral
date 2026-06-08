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
}
