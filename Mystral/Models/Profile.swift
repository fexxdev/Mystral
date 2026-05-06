import Foundation

struct CurvePoint: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var temperature: Double {
        didSet { temperature = min(max(temperature, 0), 120) }
    }
    var fanPercentage: Double {
        didSet { fanPercentage = min(max(fanPercentage, 0), 100) }
    }

    init(temperature: Double, fanPercentage: Double) {
        self.temperature = min(max(temperature, 0), 120)
        self.fanPercentage = min(max(fanPercentage, 0), 100)
    }

    enum CodingKeys: String, CodingKey {
        case temperature, fanPercentage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawTemp = try c.decode(Double.self, forKey: .temperature)
        let rawPct = try c.decode(Double.self, forKey: .fanPercentage)
        self.temperature = min(max(rawTemp, 0), 120)
        self.fanPercentage = min(max(rawPct, 0), 100)
    }
}

extension Array where Element == CurvePoint {
    func sortedByTemperature() -> [CurvePoint] {
        sorted { $0.temperature < $1.temperature }
    }
}

enum ProfileTrigger: Codable, Equatable, Sendable {
    case powerSource(PowerSource)
    case thermalState(ThermalLevel)
    case frontmostApp(bundleId: String)

    enum PowerSource: String, Codable, Sendable, CaseIterable { case ac, battery }
    enum ThermalLevel: String, Codable, Sendable, CaseIterable {
        case nominal, fair, serious, critical
    }
}

struct Profile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var icon: String
    var isPreset: Bool
    var curvePoints: [CurvePoint]
    var sensorKey: String
    var fanCurves: [Int: [CurvePoint]]?
    var triggers: [ProfileTrigger]?

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "fan",
        isPreset: Bool = false,
        curvePoints: [CurvePoint],
        sensorKey: String = "",
        fanCurves: [Int: [CurvePoint]]? = nil,
        triggers: [ProfileTrigger]? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isPreset = isPreset
        self.curvePoints = curvePoints
        self.sensorKey = sensorKey
        self.fanCurves = fanCurves
        self.triggers = triggers
    }

    func curve(for fanIndex: Int) -> [CurvePoint] {
        fanCurves?[fanIndex] ?? curvePoints
    }

    func hasOverride(for fanIndex: Int) -> Bool {
        fanCurves?[fanIndex] != nil
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, isPreset, curvePoints, sensorKey, fanCurves, triggers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decode(String.self, forKey: .icon)
        isPreset = try c.decode(Bool.self, forKey: .isPreset)
        curvePoints = try c.decode([CurvePoint].self, forKey: .curvePoints)
        sensorKey = try c.decodeIfPresent(String.self, forKey: .sensorKey) ?? ""
        if let stringKeyed = try? c.decode([String: [CurvePoint]].self, forKey: .fanCurves) {
            var byInt: [Int: [CurvePoint]] = [:]
            for (k, v) in stringKeyed { if let i = Int(k) { byInt[i] = v } }
            fanCurves = byInt.isEmpty ? nil : byInt
        } else {
            fanCurves = nil
        }
        triggers = try c.decodeIfPresent([ProfileTrigger].self, forKey: .triggers)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(icon, forKey: .icon)
        try c.encode(isPreset, forKey: .isPreset)
        try c.encode(curvePoints, forKey: .curvePoints)
        try c.encode(sensorKey, forKey: .sensorKey)
        if let fc = fanCurves {
            let stringKeyed = Dictionary(uniqueKeysWithValues: fc.map { (String($0.key), $0.value) })
            try c.encode(stringKeyed, forKey: .fanCurves)
        }
        try c.encodeIfPresent(triggers, forKey: .triggers)
    }
}
