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

    private(set) var sensors: [Sensor] = []
    private(set) var fans: [Fan] = []
    private(set) var isRunning = false

    var pollingInterval: TimeInterval = 2.0 {
        didSet { if isRunning { restart() } }
    }

    var manualOverrides: [Int: Double] = [:]

    init(smcService: SMCServiceProtocol, profileManager: ProfileManager) {
        self.smcService = smcService
        self.profileManager = profileManager
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
                let ratio = (temperature - low.temperature) / (high.temperature - low.temperature)
                return low.fanPercentage + ratio * (high.fanPercentage - low.fanPercentage)
            }
        }
        return sorted[sorted.count - 1].fanPercentage
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        restoreAutoMode()
    }

    func restart() { stop(); start() }

    private func tick() {
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
            applyActiveProfile()
        } catch {
            logger.error("SMC read failed: \(error.localizedDescription)")
        }
    }

    private var forcedModeSet = false

    private func applyActiveProfile() {
        guard let profile = profileManager.activeProfile else { return }
        let drivingTemp = resolveDrivingTemperature(for: profile)
        let targetPercentage = Self.interpolate(temperature: drivingTemp, curve: profile.curvePoints)

        if !forcedModeSet {
            do {
                try smcService.setForcedMode(fanCount: fans.count, forced: true)
                forcedModeSet = true
            } catch {
                logger.warning("Failed to enable forced fan mode: \(error.localizedDescription)")
            }
        }

        for fan in fans {
            let percentage = manualOverrides[fan.id] ?? targetPercentage
            do {
                try smcService.setFanSpeed(index: fan.id, percentage: percentage)
            } catch {
                logger.warning("Fan \(fan.id) write failed: \(error.localizedDescription)")
            }
        }
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
