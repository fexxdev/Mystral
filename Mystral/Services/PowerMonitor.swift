import Foundation

/// Reads instantaneous power: total system power from SMC `PSTR`, and CPU/GPU
/// power from IOReport. All reads are user-level (no root). Sampled once per
/// menu-bar timer tick by `MenuBarManager`.
@Observable
@MainActor
final class PowerMonitor {
    private(set) var totalWatts: Double?
    private(set) var cpuWatts: Double?
    private(set) var gpuWatts: Double?

    private let smc: SMCKit?
    private let ioreport: IOReportPower?

    init() {
        let kit = SMCKit()
        var opened: SMCKit?
        do { try kit.open(); opened = kit } catch { opened = nil }
        smc = opened
        ioreport = IOReportPower()
    }

    func sample() {
        if let smc, let watts = try? smc.readFloat(key: "PSTR"), watts > 0 {
            totalWatts = watts
        } else {
            totalWatts = nil
        }
        if let reading = ioreport?.sample() {
            cpuWatts = reading.cpu
            gpuWatts = reading.gpu
        } else {
            cpuWatts = nil
            gpuWatts = nil
        }
    }
}
