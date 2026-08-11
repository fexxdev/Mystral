import XCTest
import SwiftUI
@testable import Mystral

final class PowerMonitorTests: XCTestCase {

    // MARK: - History capping

    func testAppendCappedGrows() {
        let h = PowerMonitor.appendCapped(5, to: [1, 2, 3], maxHistory: 10)
        XCTAssertEqual(h, [1, 2, 3, 5])
    }

    func testAppendCappedTrimsOldest() {
        let h = PowerMonitor.appendCapped(4, to: [1, 2, 3], maxHistory: 3)
        XCTAssertEqual(h, [2, 3, 4])
    }

    func testAppendCappedExactlyAtLimit() {
        let h = PowerMonitor.appendCapped(3, to: [1, 2], maxHistory: 3)
        XCTAssertEqual(h, [1, 2, 3])
    }

    // MARK: - "Other" power attribution

    func testOtherWattsSubtractsKnown() {
        XCTAssertEqual(PowerCard.otherWatts(total: 40, cpu: 17, gpu: 4), 19, accuracy: 0.0001)
    }

    func testOtherWattsClampsAtZero() {
        XCTAssertEqual(PowerCard.otherWatts(total: 10, cpu: 8, gpu: 5), 0, accuracy: 0.0001)
    }

    func testOtherWattsHandlesNilComponents() {
        XCTAssertEqual(PowerCard.otherWatts(total: 30, cpu: nil, gpu: 4), 26, accuracy: 0.0001)
    }

    func testHistoryLimitKeepsFiveMinutesAtEachPollingInterval() {
        XCTAssertEqual(FanController.historyLimit(forPollingInterval: 2), 151)
        XCTAssertEqual(FanController.historyLimit(forPollingInterval: 5), 61)
        XCTAssertEqual(FanController.historyLimit(forPollingInterval: 10), 31)
    }
}
