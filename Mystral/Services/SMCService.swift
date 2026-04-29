import Foundation

protocol SMCServiceProtocol: Sendable {
    func getAllSensors() throws -> [Sensor]
    func readTemperature(key: String) throws -> Double
    func getAllFans() throws -> [Fan]
    func readFanSpeed(index: Int) throws -> Int
    func setFanSpeed(index: Int, percentage: Double) throws
    func setFanMode(index: Int, mode: FanMode) throws
}

final class SMCService: SMCServiceProtocol {
    private let smc = SMCKit()

    private static let knownSensorNames: [String: String] = [
        "Tp01": "CPU Performance Core 1",
        "Tp02": "CPU Performance Core 2",
        "Tp03": "CPU Performance Core 3",
        "Tp04": "CPU Performance Core 4",
        "Tp05": "CPU Performance Core 5",
        "Tp06": "CPU Performance Core 6",
        "Tp09": "CPU Efficiency Core 1",
        "Tp0A": "CPU Efficiency Core 2",
        "Tp0B": "CPU Efficiency Core 3",
        "Tp0C": "CPU Efficiency Core 4",
        "Tg0a": "GPU Core 1",
        "Tg0b": "GPU Core 2",
        "Tg0c": "GPU Core 3",
        "Tg0d": "GPU Core 4",
        "TaLP": "Airflow Left",
        "TaRP": "Airflow Right",
        "Tm01": "Memory 1",
        "Tm02": "Memory 2",
        "Ts0S": "SSD",
    ]

    init() throws {
        try smc.open()
    }

    deinit { smc.close() }

    func getAllSensors() throws -> [Sensor] {
        let keys = try smc.temperatureKeys()
        return keys.compactMap { key in
            guard let temp = try? smc.readFloat(key: key), temp > 0, temp < 150 else { return nil }
            let name = Self.knownSensorNames[key] ?? key
            return Sensor(id: key, name: name, temperature: temp)
        }
    }

    func readTemperature(key: String) throws -> Double {
        try smc.readFloat(key: key)
    }

    func getAllFans() throws -> [Fan] {
        let count = try smc.readInteger(key: "FNum")
        return (0..<count).compactMap { i in
            let prefix = "F\(i)"
            guard let actual = try? smc.readFloat(key: "\(prefix)Ac"),
                  let min = try? smc.readFloat(key: "\(prefix)Mn"),
                  let max = try? smc.readFloat(key: "\(prefix)Mx") else { return nil }
            let target = (try? smc.readFloat(key: "\(prefix)Tg")) ?? actual
            let modeRaw = (try? smc.readInteger(key: "\(prefix)Md")) ?? 0
            let name = i == 0 ? "Left Fan" : "Right Fan"
            return Fan(id: i, name: name, currentRPM: Int(actual), targetRPM: Int(target),
                       minRPM: Int(min), maxRPM: Int(max), mode: FanMode(rawValue: modeRaw) ?? .auto)
        }
    }

    func readFanSpeed(index: Int) throws -> Int { try smc.readInteger(key: "F\(index)Ac") }

    func setFanSpeed(index: Int, percentage: Double) throws {
        let fans = try getAllFans()
        guard index < fans.count else { return }
        let fan = fans[index]
        let targetRPM = Double(fan.minRPM) + (Double(fan.maxRPM - fan.minRPM) * percentage / 100.0)
        try smc.writeFpe2(key: "F\(index)Tg", value: targetRPM)
    }

    func setFanMode(index: Int, mode: FanMode) throws {
        try smc.writeUInt8(key: "F\(index)Md", value: UInt8(mode.rawValue))
    }
}
