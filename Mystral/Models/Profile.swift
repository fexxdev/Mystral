import Foundation

struct CurvePoint: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var temperature: Double
    var fanPercentage: Double

    enum CodingKeys: String, CodingKey {
        case temperature, fanPercentage
    }
}

extension Array where Element == CurvePoint {
    func sortedByTemperature() -> [CurvePoint] {
        sorted { $0.temperature < $1.temperature }
    }
}

struct Profile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var icon: String
    var isPreset: Bool
    var curvePoints: [CurvePoint]
    var sensorKey: String

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "fan",
        isPreset: Bool = false,
        curvePoints: [CurvePoint],
        sensorKey: String = ""
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isPreset = isPreset
        self.curvePoints = curvePoints
        self.sensorKey = sensorKey
    }
}
