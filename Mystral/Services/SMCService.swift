import Foundation
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "SMCService")

protocol SMCServiceProtocol: Sendable {
    func getAllSensors() throws -> [Sensor]
    func readTemperature(key: String) throws -> Double
    func getAllFans() throws -> [Fan]
    func readFanSpeed(index: Int) throws -> Int
    func setFanSpeed(index: Int, percentage: Double) throws
    func setFanMode(index: Int, mode: FanMode) throws
    func setForcedMode(fanCount: Int, forced: Bool) throws
}

final class SMCService: SMCServiceProtocol, @unchecked Sendable {
    private let smc = SMCKit()

    private struct FanMetadata {
        let minRPM: Double
        let maxRPM: Double
    }

    private var fanMetadataCache: [Int: FanMetadata] = [:]
    private var fanCount: Int?
    private var ftstUnlocked = false
    private let ftstAvailable: Bool

    init() throws {
        try smc.open()
        ftstAvailable = smc.keyExists("Ftst")
        logger.info("Ftst key available: \(self.ftstAvailable)")
    }

    deinit { close() }

    func close() {
        if ftstUnlocked {
            try? smc.tryWriteUInt8(key: "Ftst", value: 0)
            ftstUnlocked = false
        }
        smc.close()
    }

    func getAllSensors() throws -> [Sensor] {
        let keys = try smc.temperatureKeys()
        return keys.compactMap { key in
            guard let temp = try? smc.readFloat(key: key), temp > 0, temp < 150 else { return nil }
            return Sensor(id: key, name: SensorRegistry.nameForKey(key), temperature: temp)
        }
    }

    func readTemperature(key: String) throws -> Double {
        try smc.readFloat(key: key)
    }

    private func getFanCount() throws -> Int {
        if let cached = fanCount { return cached }
        let count = try smc.readInteger(key: "FNum")
        fanCount = count
        return count
    }

    private func getFanMetadata(index: Int) throws -> FanMetadata {
        if let cached = fanMetadataCache[index] { return cached }
        let prefix = "F\(index)"
        let min = try smc.readFloat(key: "\(prefix)Mn")
        let max = try smc.readFloat(key: "\(prefix)Mx")
        let meta = FanMetadata(minRPM: min, maxRPM: max)
        fanMetadataCache[index] = meta
        return meta
    }

    func getAllFans() throws -> [Fan] {
        let count = try getFanCount()
        return (0..<count).compactMap { i in
            let prefix = "F\(i)"
            guard let actual = try? smc.readFloat(key: "\(prefix)Ac"),
                  let meta = try? getFanMetadata(index: i) else { return nil }
            let target = (try? smc.readFloat(key: "\(prefix)Tg")) ?? actual
            let modeRaw = (try? smc.readInteger(key: "\(prefix)Md")) ?? 0
            let name = i == 0 ? "Left Fan" : "Right Fan"
            return Fan(id: i, name: name, currentRPM: Int(actual), targetRPM: Int(target),
                       minRPM: Int(meta.minRPM), maxRPM: Int(meta.maxRPM),
                       mode: FanMode(rawValue: modeRaw) ?? .auto)
        }
    }

    func readFanSpeed(index: Int) throws -> Int { try smc.readInteger(key: "F\(index)Ac") }

    func setFanSpeed(index: Int, percentage: Double) throws {
        if !ftstUnlocked {
            try unlockFanControl()
        }
        let meta = try getFanMetadata(index: index)
        let clamped = max(0, min(100, percentage))
        let targetRPM = meta.minRPM + (meta.maxRPM - meta.minRPM) * clamped / 100.0
        let code = try smc.tryWriteFloat(key: "F\(index)Tg", value: targetRPM)
        if code != 0 && code != 0x87 {
            throw SMCError.writeError(kern_return_t(code))
        }
    }

    func setFanMode(index: Int, mode: FanMode) throws {
        try ensureFanMode(index: index, target: UInt8(mode.rawValue))
    }

    func setForcedMode(fanCount: Int, forced: Bool) throws {
        if forced {
            try unlockFanControl()
            for i in 0..<fanCount {
                try ensureFanMode(index: i, target: 1)
            }
        } else {
            for i in 0..<fanCount {
                _ = try? smc.tryWriteUInt8(key: "F\(i)Md", value: 0)
            }
            if ftstAvailable && ftstUnlocked {
                _ = try? smc.tryWriteUInt8(key: "Ftst", value: 0)
                ftstUnlocked = false
            }
        }
    }

    func reUnlockAfterWake(fanCount: Int) throws {
        ftstUnlocked = false
        try unlockFanControl()
        for i in 0..<fanCount {
            try ensureFanMode(index: i, target: 1)
        }
    }

    private func unlockFanControl() throws {
        guard ftstAvailable else {
            ftstUnlocked = true
            return
        }
        let code = try smc.tryWriteUInt8(key: "Ftst", value: 1)
        if code != 0 {
            logger.warning("Ftst write returned 0x\(String(code, radix: 16)) — proceeding anyway")
        }
        ftstUnlocked = true
        usleep(500_000)
    }

    private func ensureFanMode(index: Int, target: UInt8) throws {
        let key = "F\(index)Md"
        let direct = try smc.tryWriteUInt8(key: key, value: target)
        if direct == 0 { return }
        if direct != 0x82 && direct != 0x84 {
            throw SMCError.writeError(kern_return_t(direct))
        }
        if target == 1 && !ftstUnlocked { try unlockFanControl() }
        let deadline = Date().addingTimeInterval(10.0)
        var lastCode: UInt8 = direct
        while Date() < deadline {
            let code = try smc.tryWriteUInt8(key: key, value: target)
            if code == 0 {
                logger.info("\(key)=\(target) accepted after retry")
                return
            }
            lastCode = code
            usleep(100_000)
        }
        throw SMCError.writeError(kern_return_t(lastCode))
    }
}
