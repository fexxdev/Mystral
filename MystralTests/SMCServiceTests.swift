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

    func getAllSensors() throws -> [Sensor] { sensors }
    func readTemperature(key: String) throws -> Double { sensors.first { $0.id == key }?.temperature ?? 0 }
    func getAllFans() throws -> [Fan] { fans }
    func readFanSpeed(index: Int) throws -> Int { fans[index].currentRPM }
    func setFanSpeed(index: Int, percentage: Double) throws { lastSetFanIndex = index; lastSetPercentage = percentage }
    func setFanMode(index: Int, mode: FanMode) throws { lastSetMode = mode }
    func setForcedMode(fanCount: Int, forced: Bool) throws {}
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
}
