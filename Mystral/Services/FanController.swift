import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "FanController")

protocol ProfileActivationStrategy: Sendable {
    func shouldActivate(profile: Profile, sensors: [Sensor]) -> Bool
}

struct ManualActivationStrategy: ProfileActivationStrategy {
    func shouldActivate(profile: Profile, sensors: [Sensor]) -> Bool { false }
}

@Observable
@MainActor
final class FanController {
    private let smcService: SMCServiceProtocol
    private let profileManager: ProfileManager
    private var timer: Timer?

    /// Power readings, sampled once per tick so their history shares the polling
    /// cadence with sensor history (consumed by the dashboard's power chart and the
    /// menu bar). Sampling lives here, in the single authoritative poll loop.
    let powerMonitor = PowerMonitor()

    private(set) var sensors: [Sensor] = []
    private(set) var fans: [Fan] = []
    private(set) var isRunning = false
    private(set) var isHelperResponsive = true
    private var consecutiveHelperFailures = 0
    private var lastHelperRestartUptime: TimeInterval = 0
    private var wakeGraceUntil: TimeInterval = 0
    var helperRestarter: (() -> Void)?
    var manualHelperRestarter: (() -> Void)?

    var pollingInterval: TimeInterval = 2.0 {
        didSet { if isRunning { restart() } }
    }

    var manualOverrides: [Int: Double] = [:]

    var smoothingAlpha: Double = 0.3
    var deadbandPercent: Double = 3.0
    var smoothingEnabled: Bool = true {
        didSet { if !smoothingEnabled { smoothedTemps.removeAll() } }
    }
    var minimumFanPercentage: Double = 0
    var aggressiveOverrideEnabled: Bool = true
    private var smoothedTemps: [String: Double] = [:]
    private var lastWrittenPct: [Int: Double] = [:]
    private var ticksSinceForcedReassert = 0

    var alertManager: AlertManager?

    init(smcService: SMCServiceProtocol, profileManager: ProfileManager) {
        self.smcService = smcService
        self.profileManager = profileManager
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )
    }

    @objc private func handleWake() {
        logger.info("System woke — re-applying forced fan mode on next tick, granting helper 15s grace")
        forcedModeSet = false
        consecutiveHelperFailures = 0
        wakeGraceUntil = ProcessInfo.processInfo.systemUptime + 15
        if let proxy = smcService as? SMCProxyService {
            proxy.notifyWake()
        } else if let direct = smcService as? SMCService {
            direct.notifyWake()
        }
    }

    static func interpolate(temperature: Double, curve: [CurvePoint]) -> Double {
        guard !curve.isEmpty else { return 0 }
        let sorted = curve.sortedByTemperature()
        if sorted.count == 1 { return sorted[0].fanPercentage }
        if temperature <= sorted[0].temperature { return sorted[0].fanPercentage }
        if temperature >= sorted[sorted.count - 1].temperature { return sorted[sorted.count - 1].fanPercentage }
        for i in 0..<(sorted.count - 1) {
            let low = sorted[i]; let high = sorted[i + 1]
            if temperature >= low.temperature && temperature <= high.temperature {
                let range = high.temperature - low.temperature
                if range <= 0 { return low.fanPercentage }
                let ratio = (temperature - low.temperature) / range
                return low.fanPercentage + ratio * (high.fanPercentage - low.fanPercentage)
            }
        }
        return sorted[sorted.count - 1].fanPercentage
    }

    func start() {
        guard !isRunning else {
            logger.info("start() called but already running — no-op")
            return
        }
        logger.info("start() — interval=\(self.pollingInterval, privacy: .public)s")
        isRunning = true
        tick()
        let t = Timer(timeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        logger.info("stop() — invalidating timer, restoring auto mode")
        timer?.invalidate()
        timer = nil
        isRunning = false
        restoreAutoMode()
    }

    func restart() {
        logger.info("restart()")
        stop(); start()
    }

    private func tick() {
        powerMonitor.sample()
        do {
            var newSensors = try smcService.getAllSensors()
            let historyMap = Dictionary(uniqueKeysWithValues: sensors.map { ($0.id, $0.history) })
            for i in newSensors.indices {
                if let existingHistory = historyMap[newSensors[i].id] {
                    newSensors[i].history = existingHistory
                }
                newSensors[i].recordTemperature(newSensors[i].temperature)
            }
            sensors = newSensors
            fans = try smcService.getAllFans()
            logger.debug("tick — sensors=\(newSensors.count, privacy: .public), fans=\(self.fans.count, privacy: .public)")

            if consecutiveHelperFailures > 0 {
                logger.info("Helper recovered after \(self.consecutiveHelperFailures, privacy: .public) consecutive failures")
                consecutiveHelperFailures = 0
            }
            isHelperResponsive = true

            applyActiveProfile()
            alertManager?.evaluate(sensors: sensors, fans: fans, expectedFanPercent: lastWrittenPct)
        } catch {
            consecutiveHelperFailures += 1
            isHelperResponsive = false
            logger.error("SMC read failed (\(self.consecutiveHelperFailures, privacy: .public) consecutive): \(error.localizedDescription, privacy: .public)")
            attemptHelperRestart()
        }
    }

    private static let restartCooldown: TimeInterval = 30

    private func attemptHelperRestart() {
        guard consecutiveHelperFailures >= 3 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now < wakeGraceUntil {
            logger.info("Suppressing helper restart during wake grace period")
            return
        }
        guard lastHelperRestartUptime == 0 || (now - lastHelperRestartUptime > Self.restartCooldown) else { return }
        logger.info("Triggering helper restart (failures=\(self.consecutiveHelperFailures, privacy: .public))")
        lastHelperRestartUptime = now
        forcedModeSet = false
        lastWrittenPct.removeAll()
        if let proxy = smcService as? SMCProxyService {
            proxy.purgeStaleCommands()
        }
        helperRestarter?()
    }

    private var forcedModeSet = false

    private func applyActiveProfile() {
        guard let profile = profileManager.activeProfile else { return }
        guard !fans.isEmpty else { return }

        let reassertNeeded: Bool
        if aggressiveOverrideEnabled {
            ticksSinceForcedReassert += 1
            reassertNeeded = !forcedModeSet || ticksSinceForcedReassert >= 5
        } else {
            reassertNeeded = !forcedModeSet
        }
        if reassertNeeded {
            do {
                try smcService.setForcedMode(fanCount: fans.count, forced: true)
                forcedModeSet = true
                ticksSinceForcedReassert = 0
            } catch {
                logger.info("Forced fan mode not available (expected on M3/M4 Pro/Max): \(error.localizedDescription, privacy: .public)")
            }
        }

        let rawTemp = resolveDrivingTemperature(for: profile)
        let drivingTemp = smoothingEnabled
            ? smooth(key: profile.sensorKey.isEmpty ? "_avg" : profile.sensorKey, raw: rawTemp)
            : rawTemp

        for fan in fans {
            let curve = profile.curve(for: fan.id)
            let curveTarget = Self.interpolate(temperature: drivingTemp, curve: curve)
            let manualValue = manualOverrides[fan.id]
            let basePercentage = manualValue ?? curveTarget
            let percentage = max(basePercentage, minimumFanPercentage)
            let last = lastWrittenPct[fan.id]
            let isManual = manualValue != nil || minimumFanPercentage > 0
            let band = (isManual || aggressiveOverrideEnabled) ? 0.0 : deadbandPercent
            if let last = last, abs(percentage - last) < band {
                continue
            }
            do {
                try smcService.setFanSpeed(index: fan.id, percentage: percentage)
                lastWrittenPct[fan.id] = percentage
            } catch {
                logger.warning("Fan \(fan.id, privacy: .public) write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func smooth(key: String, raw: Double) -> Double {
        let alpha = max(0.05, min(1.0, smoothingAlpha))
        if let prev = smoothedTemps[key] {
            let next = alpha * raw + (1 - alpha) * prev
            smoothedTemps[key] = next
            return next
        }
        smoothedTemps[key] = raw
        return raw
    }

    private func resolveDrivingTemperature(for profile: Profile) -> Double {
        if !profile.sensorKey.isEmpty, let sensor = sensors.first(where: { $0.id == profile.sensorKey }) {
            return sensor.temperature
        }
        if let cpuMax = sensors.first(where: { $0.id == SensorRegistry.defaultCpuSensorKey }) {
            return cpuMax.temperature
        }
        let cpuCores = SensorRegistry.cpuCoreSensors(from: sensors)
        guard !cpuCores.isEmpty else { return sensors.first?.temperature ?? 0 }
        return cpuCores.map(\.temperature).reduce(0, +) / Double(cpuCores.count)
    }

    func requestManualRestart() {
        consecutiveHelperFailures = 0
        isHelperResponsive = false
        manualHelperRestarter?()
    }

    func clearManualOverride(for fanId: Int) { manualOverrides.removeValue(forKey: fanId) }
    func clearAllManualOverrides() { manualOverrides.removeAll() }

    private func restoreAutoMode() {
        do {
            try smcService.setForcedMode(fanCount: max(fans.count, 2), forced: false)
            forcedModeSet = false
        } catch {
            logger.warning("Failed to restore auto mode: \(error.localizedDescription)")
        }
    }
}
