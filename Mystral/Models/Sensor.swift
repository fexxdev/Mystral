import Foundation

struct Sensor: Identifiable, Sendable {
    let id: String
    let name: String
    var temperature: Double
    var history: [Double]
    /// True when `temperature` is this sensor's last live reading rather than this
    /// tick's: the SMC switched the key off for a moment (see `SensorHistoryStore`).
    var isHeld: Bool
    /// True for a held reading older than `SensorHistoryStore.cpuFreshDuration`. The
    /// sensor stays listed so the count does not jump, but it no longer counts in the
    /// CPU maximum, the average or a fan curve.
    var isStale: Bool

    init(id: String, name: String, temperature: Double = 0, history: [Double] = [],
         isHeld: Bool = false, isStale: Bool = false) {
        self.id = id
        self.name = name
        self.temperature = temperature
        self.history = history
        self.isHeld = isHeld
        self.isStale = isStale
    }

    mutating func recordTemperature(_ temp: Double, maxHistory: Int = 150) {
        temperature = temp
        history.append(temp)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }
}
