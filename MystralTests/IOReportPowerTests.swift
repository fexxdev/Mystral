import XCTest
@testable import Mystral

final class IOReportPowerTests: XCTestCase {
    func testNanojoules() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 1_000_000_000, unit: "nJ"), 1.0, accuracy: 1e-9)
    }

    func testMicrojoules() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 1_000_000, unit: "uJ"), 1.0, accuracy: 1e-9)
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 1_000, unit: "µJ"), 0.001, accuracy: 1e-9)
    }

    func testMillijoules() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 1_000, unit: "mJ"), 1.0, accuracy: 1e-9)
    }

    func testJoulesDefault() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 5, unit: "J"), 5.0, accuracy: 1e-9)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(IOReportPower.energyToJoules(raw: 2_000, unit: "MJ"), 2.0, accuracy: 1e-9)
    }

    // MARK: - Sample sanity (issue #4)

    func testNormalReadingIsAccepted() {
        let result = IOReportPower.evaluate(cpuJoules: 40, gpuJoules: 6, elapsed: 2)
        XCTAssertEqual(result, .accept(cpu: 20, gpu: 3))
    }

    func testMissingChannelStaysNil() {
        let result = IOReportPower.evaluate(cpuJoules: 40, gpuJoules: nil, elapsed: 2)
        XCTAssertEqual(result, .accept(cpu: 20, gpu: nil))
    }

    /// Two timer ticks firing close together: 1 J over 20 ms would read as 50 W
    /// and worse spikes follow from coarser counter updates. Keep the baseline instead.
    func testShortWindowKeepsBaseline() {
        XCTAssertTrue(IOReportPower.isWindowTooShort(elapsed: 0.02, minimumInterval: 1))
        XCTAssertFalse(IOReportPower.isWindowTooShort(elapsed: 2, minimumInterval: 1))
        // Zero or negative windows are not "too short": evaluate() rebases on them.
        XCTAssertFalse(IOReportPower.isWindowTooShort(elapsed: 0, minimumInterval: 1))
    }

    func testAbsoluteMinimumIntervalAppliesEvenWhenCallerAsksForLess() {
        XCTAssertEqual(IOReportPower.effectiveMinimumInterval(0), IOReportPower.absoluteMinimumInterval)
        XCTAssertTrue(IOReportPower.isWindowTooShort(elapsed: 0.1, minimumInterval: 0))
    }

    // MARK: - CPU channel selection

    func testOnlyRollUpChannelsCount() {
        XCTAssertEqual(IOReportPower.energyChannelKind("CPU Energy"), .cpuRollUp)
        XCTAssertEqual(IOReportPower.energyChannelKind("GPU Energy"), .gpuRollUp)
        // Ultra chips publish one roll-up per die.
        XCTAssertEqual(IOReportPower.energyChannelKind("DIE_0_CPU Energy"), .cpuPerDie)
        XCTAssertEqual(IOReportPower.energyChannelKind("DIE_1_CPU Energy"), .cpuPerDie)
        XCTAssertEqual(IOReportPower.energyChannelKind("DIE_1_GPU Energy"), .gpuPerDie)
        // Sub-channels seen on an M3 Pro (macOS 27.2.1) must never count.
        for name in ["PCPU", "ECPU", "PCPU0", "ECPU0_SRAM", "PCPUDTL00", "GPU", "GPU SRAM", "DIE_0_PCPU", "ANE"] {
            XCTAssertNil(IOReportPower.energyChannelKind(name), name)
        }
    }

    /// A chip that publishes both the chip roll-up and one roll-up per die must not be counted twice.
    func testRollUpWinsOverPerDieSum() {
        XCTAssertEqual(IOReportPower.wholeChipEnergy(rollUp: 30, perDie: 30), 30)
        XCTAssertEqual(IOReportPower.wholeChipEnergy(rollUp: nil, perDie: 30), 30)
        XCTAssertNil(IOReportPower.wholeChipEnergy(rollUp: nil, perDie: nil))
    }

    func testContinuousClockAdvances() {
        let a = IOReportPower.continuousTime()
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertGreaterThan(IOReportPower.continuousTime() - a, 0.04)
    }

    func testImplausibleWattageIsRejected() {
        // The spike in issue #4: about 1,900 W of CPU power for one sample.
        let result = IOReportPower.evaluate(cpuJoules: 3_800, gpuJoules: 2, elapsed: 2)
        XCTAssertEqual(result, .rebase)
    }

    // MARK: - macOS 27 frozen CPU counter (vladkens/macmon#76)

    func testZeroCpuDeltaIsNoReadingNotZeroWatts() {
        let result = IOReportPower.evaluate(cpuJoules: 0, gpuJoules: 1, elapsed: 2)
        XCTAssertEqual(result, .accept(cpu: nil, gpu: 0.5))
    }

    func testZeroGpuDeltaIsARealReading() {
        let result = IOReportPower.evaluate(cpuJoules: 40, gpuJoules: 0, elapsed: 2)
        XCTAssertEqual(result, .accept(cpu: 20, gpu: 0))
    }

    /// After 4 s without movement the counter delivers 6 s of energy at once.
    /// Averaged over the whole 6 s it is 20 W, not 60 W.
    func testCatchUpIsAveragedOverTheStalledTime() {
        let result = IOReportPower.evaluate(cpuJoules: 120, gpuJoules: nil, elapsed: 2, cpuStalledFor: 4)
        XCTAssertEqual(result, .accept(cpu: 20, gpu: nil))
    }

    func testReadingFarAboveSystemTotalIsRejected() {
        // 300 W of CPU while the whole Mac draws 7 W is a catch-up spike.
        XCTAssertEqual(IOReportPower.evaluate(cpuJoules: 600, gpuJoules: nil, elapsed: 2, systemWatts: 7), .rebase)
        // A real load step ahead of the lagging SMC total is kept.
        XCTAssertEqual(IOReportPower.evaluate(cpuJoules: 27.2, gpuJoules: nil, elapsed: 2, systemWatts: 1.2),
                       .accept(cpu: 13.6, gpu: nil))
    }

    func testCeilingFallsBackWithoutSystemTotal() {
        XCTAssertEqual(IOReportPower.ceilingWatts(systemWatts: nil), IOReportPower.maximumPlausibleWatts)
        XCTAssertEqual(IOReportPower.ceilingWatts(systemWatts: 7), 170)
        XCTAssertEqual(IOReportPower.ceilingWatts(systemWatts: 200), IOReportPower.maximumPlausibleWatts)
    }

    // MARK: - CLPC energy counters (macOS 27)

    func testCLPCReportIDsMatchKnownFullIDs() {
        // Full IDs from macmon's 27.0.1 catalog: M1 Ultra, M2, M5.
        let expected: [String: [UInt64]] = [
            "com.apple.driver.AppleT6002CLPC": [0x0000_0010_b501_816b, 0x0000_0019_9e2c_3e8b],
            "com.apple.driver.AppleT8112CLPC": [0x0000_0010_b543_5137, 0x0000_0019_638d_9d52],
            "com.apple.driver.AppleT8142CLPC": [0x0000_0010_4370_8744, 0x0000_0019_6a01_0933],
        ]
        for (bundle, ids) in expected {
            let channels = CLPCEnergyChannels.channels(bundle: bundle, osMajor: 27)
            XCTAssertEqual(channels?.map(\.id), ids, bundle)
            XCTAssertEqual(channels?.map(\.name), ["CPU Energy", "GPU Energy"], bundle)
        }
    }

    func testCLPCLeavesUnknownDriversAndOtherVersionsToTheEnergyModel() {
        XCTAssertNil(CLPCEnergyChannels.channels(bundle: "com.apple.driver.AppleUnknownCLPC", osMajor: 27))
        XCTAssertNil(CLPCEnergyChannels.channels(bundle: "AppleT8112CLPC", osMajor: 27))
        for major in [15, 26, 28] {
            XCTAssertNil(CLPCEnergyChannels.channels(bundle: "com.apple.driver.AppleT8112CLPC", osMajor: major))
        }
    }

    func testCLPCChannelIDsAreUniquePerDriver() {
        XCTAssertEqual(CLPCEnergyChannels.knownBundles.count, 17)
        for bundle in CLPCEnergyChannels.knownBundles {
            let ids = CLPCEnergyChannels.channels(bundle: bundle, osMajor: 27)?.map(\.id) ?? []
            XCTAssertEqual(Set(ids).count, 2, bundle)
        }
    }

    func testCLPCDescriptorFields() {
        let channel = CLPCEnergyChannels.Channel(id: 0x0000_0010_be03_a01a, name: "CPU Energy")
        let d = CLPCEnergyChannels.descriptor(driverID: 0x1_0000_0428, channel: channel)
        XCTAssertEqual(d["DriverID"] as? Int64, 0x1_0000_0428)
        XCTAssertEqual(d["DriverName"] as? String, "AppleCLPC")
        XCTAssertEqual(d["IOReportGroupName"] as? String, "CLPC")
        XCTAssertEqual(d["IOReportSubGroupName"] as? String, "Energy Counters")
        let legend = d["LegendChannel"] as? [Any]
        XCTAssertEqual(legend?[0] as? Int64, 0x0000_0010_be03_a01a)
        XCTAssertEqual(legend?[1] as? Int64, 0x1_0002_0001)
        XCTAssertEqual(legend?[2] as? String, "CPU Energy")
        let info = d["IOReportChannelInfo"] as? [String: Any]
        XCTAssertEqual(info?["IOReportChannelUnit"] as? Int64, 0x0300_0076_0000_0000)
    }

    func testCLPCReadingWinsOverFrozenEnergyModel() {
        var clpc = IOReportPower.EnergyReading()
        clpc.addCPU(30)
        var model = IOReportPower.EnergyReading()
        model.addCPU(0)   // frozen on macOS 27
        model.addGPU(2)
        let chosen = IOReportPower.preferred(clpc: clpc, energyModel: model)
        XCTAssertEqual(chosen, IOReportPower.EnergyReading(cpu: 30, gpu: 2))
    }

    func testEnergyModelIsUsedWithoutCLPC() {
        var model = IOReportPower.EnergyReading()
        model.addCPU(10); model.addCPU(5)   // two dies on an Ultra
        let chosen = IOReportPower.preferred(clpc: .init(), energyModel: model)
        XCTAssertEqual(chosen, IOReportPower.EnergyReading(cpu: 15, gpu: nil))
    }

    func testNegativeDeltaIsRejected() {
        let result = IOReportPower.evaluate(cpuJoules: -5, gpuJoules: 2, elapsed: 2)
        XCTAssertEqual(result, .rebase)
    }

    func testNonFiniteInputsAreRejected() {
        XCTAssertEqual(IOReportPower.evaluate(cpuJoules: .nan, gpuJoules: nil, elapsed: 2), .rebase)
        XCTAssertEqual(IOReportPower.evaluate(cpuJoules: 10, gpuJoules: nil, elapsed: 0), .rebase)
        XCTAssertEqual(IOReportPower.evaluate(cpuJoules: 10, gpuJoules: nil, elapsed: -1), .rebase)
    }
}
