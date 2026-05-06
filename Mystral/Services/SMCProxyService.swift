import Foundation
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "SMCProxyService")

enum SMCProxyError: Error, LocalizedError {
    case helperNotResponding

    var errorDescription: String? {
        switch self {
        case .helperNotResponding: "SMC helper process is not responding"
        }
    }
}

final class SMCProxyService: SMCServiceProtocol, @unchecked Sendable {
    private var cachedSensors: [Sensor] = []
    private var cachedFans: [Fan] = []
    private let startTime = Date()
    private static let staleThreshold: TimeInterval = 10
    private static let startupGrace: TimeInterval = 60
    private var lastRefreshUptime: TimeInterval = 0
    private static let refreshCooldown: TimeInterval = 0.5
    private var helperAlive = true

    func getAllSensors() throws -> [Sensor] {
        try refreshData()
        return cachedSensors
    }

    func readTemperature(key: String) throws -> Double {
        try refreshData()
        return cachedSensors.first { $0.id == key }?.temperature ?? 0
    }

    func getAllFans() throws -> [Fan] {
        try refreshData()
        return cachedFans
    }

    func readFanSpeed(index: Int) throws -> Int {
        try refreshData()
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

    private func refreshData() throws {
        let fm = FileManager.default
        let path = SMCHelperMode.dataPath

        // Staleness check always runs regardless of cooldown
        try checkHelperHealth(fm: fm, path: path)

        // Skip full I/O if we already refreshed this tick
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastRefreshUptime < Self.refreshCooldown {
            return
        }

        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            logger.warning("refreshData — failed to read data file at \(path, privacy: .public)")
            return
        }
        guard let smcData = try? JSONDecoder().decode(SMCHelperMode.SMCData.self, from: data) else {
            logger.warning("refreshData — failed to decode SMCData (size=\(data.count, privacy: .public) bytes)")
            return
        }

        cachedSensors = smcData.sensors.map {
            Sensor(id: $0.key, name: $0.name, temperature: $0.temperature)
        }
        cachedFans = smcData.fans.map {
            Fan(id: $0.id, name: $0.name, currentRPM: $0.currentRPM, targetRPM: $0.targetRPM,
                minRPM: $0.minRPM, maxRPM: $0.maxRPM, mode: FanMode(rawValue: $0.mode) ?? .auto)
        }
        lastRefreshUptime = now
        helperAlive = true
        logger.debug("refreshData — decoded \(self.cachedSensors.count, privacy: .public) sensors, \(self.cachedFans.count, privacy: .public) fans")
    }

    private func checkHelperHealth(fm: FileManager, path: String) throws {
        guard fm.fileExists(atPath: path) else {
            if Date().timeIntervalSince(startTime) > Self.startupGrace {
                helperAlive = false
                throw SMCProxyError.helperNotResponding
            }
            logger.debug("refreshData — data file not yet available (startup grace)")
            return
        }

        if let attrs = try? fm.attributesOfItem(atPath: path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) > Self.staleThreshold {
            helperAlive = false
            logger.warning("refreshData — data file is stale (age=\(Int(Date().timeIntervalSince(modDate)))s)")
            throw SMCProxyError.helperNotResponding
        }
    }

    func purgeStaleCommands() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: SMCHelperMode.cmdDir) else { return }
        var removed = 0
        for file in files where file.hasSuffix(".json") {
            try? fm.removeItem(atPath: "\(SMCHelperMode.cmdDir)/\(file)")
            removed += 1
        }
        if removed > 0 {
            logger.info("purgeStaleCommands — removed \(removed, privacy: .public) orphaned command files")
        }
    }

    private func writeCommand(_ command: SMCHelperMode.Command) throws {
        guard helperAlive else {
            logger.debug("writeCommand skipped (helper dead) — action=\(command.action, privacy: .public)")
            return
        }
        try? FileManager.default.createDirectory(atPath: SMCHelperMode.cmdDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(command)
        let path = "\(SMCHelperMode.cmdDir)/\(UUID().uuidString).json"
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        logger.debug("writeCommand — action=\(command.action, privacy: .public), index=\(command.index, privacy: .public), value=\(command.value ?? -1, privacy: .public)")
    }
}
