import Foundation
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "SMCProxyService")

final class SMCProxyService: SMCServiceProtocol, @unchecked Sendable {
    private var cachedSensors: [Sensor] = []
    private var cachedFans: [Fan] = []

    func getAllSensors() throws -> [Sensor] {
        refreshData()
        return cachedSensors
    }

    func readTemperature(key: String) throws -> Double {
        refreshData()
        return cachedSensors.first { $0.id == key }?.temperature ?? 0
    }

    func getAllFans() throws -> [Fan] {
        refreshData()
        return cachedFans
    }

    func readFanSpeed(index: Int) throws -> Int {
        refreshData()
        return cachedFans.first { $0.id == index }?.currentRPM ?? 0
    }

    func setFanSpeed(index: Int, percentage: Double) throws {
        try writeCommand(SMCHelperMode.Command(action: "setFanSpeed", index: index, value: percentage))
    }

    func setFanMode(index: Int, mode: FanMode) throws {
        try writeCommand(SMCHelperMode.Command(action: "setFanMode", index: index, value: Double(mode.rawValue)))
    }

    func setForcedMode(fanCount: Int, forced: Bool) throws {
        try writeCommand(SMCHelperMode.Command(action: "setForcedMode", index: fanCount, value: forced ? 1 : 0))
    }

    private func refreshData() {
        let url = URL(fileURLWithPath: SMCHelperMode.dataPath)
        guard let data = try? Data(contentsOf: url),
              let smcData = try? JSONDecoder().decode(SMCHelperMode.SMCData.self, from: data) else { return }

        cachedSensors = smcData.sensors.map {
            Sensor(id: $0.key, name: $0.name, temperature: $0.temperature)
        }
        cachedFans = smcData.fans.map {
            Fan(id: $0.id, name: $0.name, currentRPM: $0.currentRPM, targetRPM: $0.targetRPM,
                minRPM: $0.minRPM, maxRPM: $0.maxRPM, mode: FanMode(rawValue: $0.mode) ?? .auto)
        }
    }

    private func writeCommand(_ command: SMCHelperMode.Command) throws {
        try? FileManager.default.createDirectory(atPath: SMCHelperMode.cmdDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(command)
        let path = "\(SMCHelperMode.cmdDir)/\(UUID().uuidString).json"
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
