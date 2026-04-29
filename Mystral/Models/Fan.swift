import Foundation

enum FanMode: Int, Sendable {
    case auto = 0
    case forced = 1
}

struct Fan: Identifiable, Sendable {
    let id: Int
    let name: String
    var currentRPM: Int
    var targetRPM: Int
    var minRPM: Int
    var maxRPM: Int
    var mode: FanMode

    var percentage: Double {
        guard maxRPM > minRPM else { return 0 }
        let pct = Double(currentRPM - minRPM) / Double(maxRPM - minRPM) * 100.0
        return max(0, min(100, pct))
    }
}
