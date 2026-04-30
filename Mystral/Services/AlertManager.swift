import Foundation
import UserNotifications
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "AlertManager")

@Observable
@MainActor
final class AlertManager {
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Keys.enabled) }
    }
    var highTempThreshold: Double {
        didSet { UserDefaults.standard.set(highTempThreshold, forKey: Keys.highTemp) }
    }
    var fanStuckEnabled: Bool {
        didSet { UserDefaults.standard.set(fanStuckEnabled, forKey: Keys.fanStuck) }
    }

    private enum Keys {
        static let enabled = "alertsEnabled"
        static let highTemp = "alertsHighTempThreshold"
        static let fanStuck = "alertsFanStuckEnabled"
    }

    private var lastHighTempAlert = Date.distantPast
    private var lastFanStuckAlert: [Int: Date] = [:]
    private var fanZeroSince: [Int: Date] = [:]
    private let cooldown: TimeInterval = 60

    private var permissionRequested = false

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.enabled) == nil {
            self.enabled = true
        } else {
            self.enabled = defaults.bool(forKey: Keys.enabled)
        }
        let storedTemp = defaults.double(forKey: Keys.highTemp)
        self.highTempThreshold = storedTemp > 0 ? storedTemp : 95
        if defaults.object(forKey: Keys.fanStuck) == nil {
            self.fanStuckEnabled = true
        } else {
            self.fanStuckEnabled = defaults.bool(forKey: Keys.fanStuck)
        }
    }

    func requestPermissionIfNeeded() {
        guard !permissionRequested else { return }
        permissionRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { logger.error("Notification auth error: \(error.localizedDescription)") }
            logger.info("Notification permission granted: \(granted)")
        }
    }

    func evaluate(sensors: [Sensor], fans: [Fan], expectedFanPercent: [Int: Double]) {
        guard enabled else { return }
        let cpuMax = sensors.filter { $0.id.hasPrefix("Tp") }.map(\.temperature).max() ?? 0
        if cpuMax >= highTempThreshold {
            tryFire(key: "highTemp", lastFire: lastHighTempAlert) {
                self.lastHighTempAlert = Date()
                self.send(
                    title: "High CPU temperature",
                    body: String(format: "CPU at %.0f°C — exceeds %.0f°C threshold", cpuMax, self.highTempThreshold)
                )
            }
        }

        guard fanStuckEnabled else { return }
        let now = Date()
        for fan in fans {
            let expected = expectedFanPercent[fan.id] ?? 0
            if fan.currentRPM == 0 && expected > 30 {
                if let since = fanZeroSince[fan.id] {
                    if now.timeIntervalSince(since) > 8 {
                        let last = lastFanStuckAlert[fan.id] ?? .distantPast
                        if now.timeIntervalSince(last) > cooldown {
                            lastFanStuckAlert[fan.id] = now
                            send(
                                title: "Fan not responding",
                                body: "\(fan.name) reading 0 RPM while target is \(Int(expected))%."
                            )
                        }
                    }
                } else {
                    fanZeroSince[fan.id] = now
                }
            } else {
                fanZeroSince.removeValue(forKey: fan.id)
            }
        }
    }

    private func tryFire(key: String, lastFire: Date, action: () -> Void) {
        guard Date().timeIntervalSince(lastFire) > cooldown else { return }
        action()
    }

    private func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { logger.error("Notification add failed: \(error.localizedDescription)") }
        }
    }
}
