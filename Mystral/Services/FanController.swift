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
    private var heartbeatTimer: Timer?

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

    nonisolated static func historyLimit(forPollingInterval interval: TimeInterval) -> Int {
        let safeInterval = max(0.1, interval)
        return max(2, Int(ceil(300 / safeInterval)) + 1)
    }

    var manualOverrides: [Int: Double] = [:]

    var smoothingAlpha: Double = 0.3
    var deadbandPercent: Double = 3.0
    var smoothingEnabled: Bool = true {
        didSet { if !smoothingEnabled { smoothedTemps.removeAll() } }
    }
    var minimumFanPercentage: Double = 0
    var aggressiveOverrideEnabled: Bool = true
    private var sensorHistories = SensorHistoryStore()
    private var smoothedTemps: [String: Double] = [:]
    private var lastWrittenPct: [Int: Double] = [:]
    private var ticksSinceForcedReassert = 0

    var alertManager: AlertManager?

    init(smcService: SMCServiceProtocol, profileManager: ProfileManager) {
        self.smcService = smcService
        self.profileManager = profileManager
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleScreensWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )
    }

    @objc nonisolated private func handleSystemWake() {
        Task { @MainActor in self.handleWakeOnMainActor(systemSlept: true) }
    }

    @objc nonisolated private func handleScreensWake() {
        Task { @MainActor in self.handleWakeOnMainActor(systemSlept: false) }
    }

    private func handleWakeOnMainActor(systemSlept: Bool) {
        logger.info("Wake (system: \(systemSlept, privacy: .public)) — re-applying forced fan mode on next tick, granting helper 15s grace")
        forcedModeSet = false
        consecutiveHelperFailures = 0
        wakeGraceUntil = ProcessInfo.processInfo.systemUptime + 15
        // Only a real system sleep breaks the power measurement; a display waking
        // up while the Mac stayed awake leaves the IOReport baseline valid.
        if systemSlept { powerMonitor.resetBaseline() }
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
        startHeartbeatIfNeeded()
    }

    /// The longest the app may go between heartbeats. The helper gives the fans back
    /// to macOS after `SMCHelperMode.heartbeatTimeout` and only looks every
    /// `tickInterval`, so a heartbeat must land well inside that window.
    nonisolated static let heartbeatInterval: TimeInterval = 3

    /// A polling tick sends a heartbeat, which is enough at the 2 s interval. At 5 s
    /// and 10 s it is not: at 10 s the helper timed out between ticks and the fans
    /// spent most of the time on automatic control. Those intervals get a separate
    /// heartbeat. Returns its period, or nil when the ticks suffice.
    nonisolated static func heartbeatPeriod(forPollingInterval interval: TimeInterval) -> TimeInterval? {
        interval > heartbeatInterval ? heartbeatInterval : nil
    }

    private func startHeartbeatIfNeeded() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        guard let period = Self.heartbeatPeriod(forPollingInterval: pollingInterval) else { return }
        let t = Timer(timeInterval: period, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                try? self.smcService.heartbeat()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        heartbeatTimer = t
    }

    func stop() {
        logger.info("stop() — invalidating timer, restoring auto mode")
        timer?.invalidate()
        timer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        isRunning = false
        restoreAutoMode()
    }

    func restart() {
        logger.info("restart()")
        stop(); start()
    }

    private func tick() {
        let historyLimit = Self.historyLimit(forPollingInterval: pollingInterval)
        powerMonitor.sample(maxHistory: historyLimit, minimumInterval: pollingInterval / 2)
        do {
            var newSensors = try smcService.getAllSensors()
            sensorHistories.carry(into: &newSensors, maxHistory: historyLimit)
            sensors = newSensors
            fans = try smcService.getAllFans()
            try smcService.heartbeat()
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
                logger.info("Forced fan mode not available: \(error.localizedDescription, privacy: .public)")
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
        return SensorRegistry.defaultDrivingTemperature(from: sensors)
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
