import Foundation

protocol ProfileActivationStrategy: Sendable {
    func shouldActivate(profile: Profile, sensors: [Sensor]) -> Bool
}

struct ManualActivationStrategy: ProfileActivationStrategy {
    func shouldActivate(profile: Profile, sensors: [Sensor]) -> Bool { false }
}

@Observable
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
        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate(); timer = nil; isRunning = false; restoreAutoMode()
    }

    func restart() { stop(); start() }

    private func tick() {
        do {
            var newSensors = try smcService.getAllSensors()
            for i in newSensors.indices {
                if let existing = sensors.first(where: { $0.id == newSensors[i].id }) {
                    newSensors[i].history = existing.history
                }
                newSensors[i].recordTemperature(newSensors[i].temperature)
            }
            sensors = newSensors
            fans = try smcService.getAllFans()
            applyActiveProfile()
        } catch {}
    }

    private func applyActiveProfile() {
        guard let profile = profileManager.activeProfile else { return }
        let drivingTemp = resolveDrivingTemperature(for: profile)
        let targetPercentage = Self.interpolate(temperature: drivingTemp, curve: profile.curvePoints)
        for fan in fans {
            let percentage = manualOverrides[fan.id] ?? targetPercentage
            do {
                try smcService.setFanMode(index: fan.id, mode: .forced)
                try smcService.setFanSpeed(index: fan.id, percentage: percentage)
            } catch {}
        }
    }

    private func resolveDrivingTemperature(for profile: Profile) -> Double {
        if !profile.sensorKey.isEmpty, let sensor = sensors.first(where: { $0.id == profile.sensorKey }) {
            return sensor.temperature
        }
        let cpuSensors = sensors.filter { $0.id.hasPrefix("Tp") }
        guard !cpuSensors.isEmpty else { return sensors.first?.temperature ?? 0 }
        return cpuSensors.map(\.temperature).reduce(0, +) / Double(cpuSensors.count)
    }

    func clearManualOverride(for fanId: Int) { manualOverrides.removeValue(forKey: fanId) }
    func clearAllManualOverrides() { manualOverrides.removeAll() }

    private func restoreAutoMode() {
        for fan in fans { try? smcService.setFanMode(index: fan.id, mode: .auto) }
    }
}
