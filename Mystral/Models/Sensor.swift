import Foundation

struct Sensor: Identifiable, Sendable {
    let id: String
    let name: String
    var temperature: Double
    var history: [Double]

    init(id: String, name: String, temperature: Double = 0, history: [Double] = []) {
        self.id = id
        self.name = name
        self.temperature = temperature
        self.history = history
    }

    mutating func recordTemperature(_ temp: Double, maxHistory: Int = 150) {
        temperature = temp
        history.append(temp)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }
}
