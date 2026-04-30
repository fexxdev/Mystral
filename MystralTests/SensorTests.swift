import XCTest
@testable import Mystral

final class SensorTests: XCTestCase {

    func testRecordTemperatureAppendsToHistory() {
        var s = Sensor(id: "Tp01", name: "Test", temperature: 0)
        s.recordTemperature(40)
        s.recordTemperature(45)
        s.recordTemperature(50)
        XCTAssertEqual(s.temperature, 50)
        XCTAssertEqual(s.history, [40, 45, 50])
    }

    func testRecordTemperatureRespectsRollingWindow() {
        var s = Sensor(id: "Tp01", name: "Test", temperature: 0)
        for i in 0..<200 { s.recordTemperature(Double(i)) }
        XCTAssertEqual(s.history.count, 150)
        XCTAssertEqual(s.history.first, 50)
        XCTAssertEqual(s.history.last, 199)
    }

    func testCustomMaxHistory() {
        var s = Sensor(id: "Tp01", name: "Test", temperature: 0)
        for i in 0..<10 { s.recordTemperature(Double(i), maxHistory: 5) }
        XCTAssertEqual(s.history.count, 5)
        XCTAssertEqual(s.history, [5, 6, 7, 8, 9])
    }
}
