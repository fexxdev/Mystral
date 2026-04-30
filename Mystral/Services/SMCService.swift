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

    init() throws {
        try smc.open()
    }

    deinit { smc.close() }

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
        let meta = try getFanMetadata(index: index)
        let targetRPM = meta.minRPM + (meta.maxRPM - meta.minRPM) * percentage / 100.0
        try smc.writeFloat(key: "F\(index)Tg", value: targetRPM)
    }

    func setFanMode(index: Int, mode: FanMode) throws {
        try smc.writeUInt8(key: "F\(index)Md", value: UInt8(mode.rawValue))
    }

    func setForcedMode(fanCount: Int, forced: Bool) throws {
        // "FS! " is a bitmask where each bit forces the corresponding fan
        let mask: UInt16 = forced ? (1 << fanCount) - 1 : 0
        try smc.writeBytes(key: "FS! ", dataType: SMCKit.DataType.ui16,
                           bytes: [UInt8(mask >> 8), UInt8(mask & 0xFF)])
    }
}
