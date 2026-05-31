import Foundation

final class IOReportPower {
    /// Convert an IOReport energy counter (with its unit label) to joules.
    /// IOReport reports different units per channel (e.g. CPU in mJ, GPU in nJ).
    static func energyToJoules(raw: Int64, unit: String) -> Double {
        let u = unit.lowercased()
        if u.contains("nj") { return Double(raw) / 1e9 }
        if u.contains("uj") || u.contains("µj") { return Double(raw) / 1e6 }
        if u.contains("mj") { return Double(raw) / 1e3 }
        return Double(raw)
    }
}
