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
    private var wakeGraceDeadline: TimeInterval = 0

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

    func heartbeat() throws {
        try writeCommand(SMCHelperMode.Command(action: "heartbeat", index: 0, value: nil))
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
            if isWithinGracePeriod() {
                logger.debug("refreshData — data file not yet available during grace period")
                return
            }
            logger.warning("refreshData — failed to read data file at \(path, privacy: .public)")
            helperAlive = false
            throw SMCProxyError.helperNotResponding
        }
        guard let smcData = try? JSONDecoder().decode(SMCHelperMode.SMCData.self, from: data) else {
            if isWithinGracePeriod() {
                logger.debug("refreshData — data file is not valid during grace period")
                return
            }
            logger.warning("refreshData — failed to decode SMCData (size=\(data.count, privacy: .public) bytes)")
            helperAlive = false
            throw SMCProxyError.helperNotResponding
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
        let now = ProcessInfo.processInfo.systemUptime
        let inGrace = now < wakeGraceDeadline || Date().timeIntervalSince(startTime) <= Self.startupGrace

        guard fm.fileExists(atPath: path) else {
            if !inGrace {
                helperAlive = false
                throw SMCProxyError.helperNotResponding
            }
            logger.debug("refreshData — data file not yet available (startup/wake grace)")
            return
        }

        if let attrs = try? fm.attributesOfItem(atPath: path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) > Self.staleThreshold {
            if inGrace {
                logger.debug("refreshData — data file stale but within wake grace period")
                return
            }
            helperAlive = false
            logger.warning("refreshData — data file is stale (age=\(Int(Date().timeIntervalSince(modDate)))s)")
            throw SMCProxyError.helperNotResponding
        }
    }

    private func isWithinGracePeriod() -> Bool {
        ProcessInfo.processInfo.systemUptime < wakeGraceDeadline
            || Date().timeIntervalSince(startTime) <= Self.startupGrace
    }

    func notifyWake() {
        wakeGraceDeadline = ProcessInfo.processInfo.systemUptime + 15
        helperAlive = true
        logger.info("Wake notification received — granting 15s grace for helper to resume")
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

    /// Asks the helper to exit so the launchd daemon's KeepAlive relaunches it (used for
    /// the manual restart button and to load a new binary after an app update). Bypasses
    /// the `helperAlive` guard since the point is to recycle a possibly-stale helper.
    func requestRestart() {
        try? SMCIPC.prepareForApp()
        let cmd = SMCHelperMode.Command(action: "restart", index: 0, value: nil)
        guard let data = try? JSONEncoder().encode(cmd) else { return }
        let path = "\(SMCHelperMode.cmdDir)/\(UUID().uuidString).json"
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        _ = chmod(path, 0o600)
        logger.info("requestRestart — wrote restart command for launchd relaunch")
    }

    private func writeCommand(_ command: SMCHelperMode.Command) throws {
        guard command.isValid else { throw SMCProxyError.helperNotResponding }
        guard helperAlive else {
            logger.debug("writeCommand skipped (helper dead) — action=\(command.action, privacy: .public)")
            throw SMCProxyError.helperNotResponding
        }
        try SMCIPC.prepareForApp()
        let data = try JSONEncoder().encode(command)
        let path = "\(SMCHelperMode.cmdDir)/\(UUID().uuidString).json"
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        guard chmod(path, 0o600) == 0 else { throw SMCIPC.IPCError.permissionDenied(path) }
        logger.debug("writeCommand — action=\(command.action, privacy: .public), index=\(command.index, privacy: .public), value=\(command.value ?? -1, privacy: .public)")
    }
}
