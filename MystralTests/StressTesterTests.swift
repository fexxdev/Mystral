import XCTest
@testable import Mystral

@MainActor
final class StressTesterTests: XCTestCase {

    func testInitialStateIsIdle() {
        let s = StressTester()
        XCTAssertEqual(s.state, .idle)
    }

    func testCancelFromIdleStaysIdle() {
        let s = StressTester()
        s.cancel()
        XCTAssertEqual(s.state, .idle)
    }

    func testStressResultEquality() {
        let r1 = StressTester.StressResult(
            baselineMaxTemp: 50, peakTemp: 80,
            baselineMaxRPM: 1000, peakRPM: 4000,
            durationSeconds: 30, fanResponded: true
        )
        let r2 = StressTester.StressResult(
            baselineMaxTemp: 50, peakTemp: 80,
            baselineMaxRPM: 1000, peakRPM: 4000,
            durationSeconds: 30, fanResponded: true
        )
        XCTAssertEqual(r1, r2)
    }

    func testFinishedStateContainsResult() {
        let r = StressTester.StressResult(
            baselineMaxTemp: 45, peakTemp: 85,
            baselineMaxRPM: 800, peakRPM: 3500,
            durationSeconds: 30, fanResponded: true
        )
        let state: StressTester.State = .finished(r)
        if case .finished(let res) = state {
            XCTAssertTrue(res.fanResponded)
            XCTAssertEqual(res.peakTemp, 85)
        } else {
            XCTFail("Expected finished state")
        }
    }
}
