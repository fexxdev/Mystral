import Foundation
import IOKit

enum HardwareInfo {

    static func modelIdentifier() -> String {
        sysctlString("hw.model")
    }

    static func chipName() -> String {
        let brand = sysctlString("machdep.cpu.brand_string")
        guard !brand.isEmpty else { return "" }
        return brand.hasPrefix("Apple ") ? String(brand.dropFirst(6)) : brand
    }

    /// Which chip this is, as far as sensor layout is concerned.
    struct Chip: Equatable, Sendable {
        enum Tier: Sendable { case base, pro, max, ultra }

        /// 1 for M1 … 6 for M6; nil for anything else (A18 Pro, unknown).
        var family: Int?
        var tier: Tier
        /// Names of the CPU performance levels the kernel reports, fastest first:
        /// ["Performance", "Efficiency"] up to M4, ["Super", "Efficiency"] on M5,
        /// ["Super", "Performance"] on M5 Pro/Max, all three on M6.
        var levelNames: [String]

        var hasSuperCores: Bool { levelNames.contains("Super") }
        var hasPerformanceCores: Bool { levelNames.contains("Performance") }

        /// A pre-M5 layout, for callers that know nothing about the chip.
        static let generic = Chip(family: nil, tier: .base, levelNames: ["Performance", "Efficiency"])

        init(family: Int?, tier: Tier, levelNames: [String]) {
            self.family = family
            self.tier = tier
            self.levelNames = levelNames
        }

        /// From a chip name such as "M3 Pro", "M5 Max" or "A18 Pro".
        init(name: String, levelNames: [String]) {
            let lower = name.lowercased()
            var family: Int?
            if let m = name.firstIndex(of: "M") {
                family = Int(name[name.index(after: m)...].prefix { $0.isNumber })
            }
            let tier: Tier
            if family == nil { tier = .base }       // "A18 Pro" is not a Pro-tier M chip
            else if lower.contains("ultra") { tier = .ultra }
            else if lower.contains("max") { tier = .max }
            else if lower.contains("pro") { tier = .pro }
            else { tier = .base }
            self.init(family: family, tier: tier, levelNames: levelNames)
        }
    }

    /// Read once: the hardware does not change while the app runs.
    static let chip = Chip(name: chipName(), levelNames: coreCounts.levels.map(\.name))

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buffer, &size, nil, 0)
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Physical core counts of this Mac. SMC temperature keys are not cores: an
    /// M3 Pro has 48 `Tp` keys for 11 CPU cores and 18 `Tg` keys for 14 GPU cores.
    struct CoreCounts: Equatable, Sendable {
        struct Level: Equatable, Sendable {
            /// The kernel's name for the level: "Performance", "Efficiency" or "Super".
            var name: String
            var cores: Int

            /// The kernel names core types in English; translate the ones we know.
            var localizedName: String {
                switch name {
                case "Performance": String(localized: "Performance", comment: "CPU core type")
                case "Efficiency": String(localized: "Efficiency", comment: "CPU core type")
                case "Super": String(localized: "Super", comment: "CPU core type")
                default: name
                }
            }
        }

        /// CPU performance levels, fastest first. Two on most chips, three on M6;
        /// empty when the system does not report them.
        var levels: [Level]
        /// 0 when unknown.
        var total: Int
        var gpu: Int

        static let unknown = CoreCounts(levels: [], total: 0, gpu: 0)

        /// "11 (5 Performance + 6 Efficiency)", with the levels the chip really has:
        /// Super + Efficiency on M5, Super + Performance on M5 Pro/Max, all three on M6.
        /// The plain count when the system reports no levels, "—" when it reports nothing.
        var cpuDescription: String {
            guard total > 0 else { return "—" }
            guard levels.count > 1 else { return "\(total)" }
            let parts = levels.map { "\($0.cores) \($0.localizedName)" }.joined(separator: " + ")
            return String(localized: "\(total) (\(parts))",
                          comment: "CPU core count: total, then the breakdown by core type, e.g. 11 (5 Performance + 6 Efficiency)")
        }
    }

    /// Read once: the hardware does not change while the app runs.
    static let coreCounts: CoreCounts = {
        // The number and names of levels differ per chip (M5 Pro has no efficiency
        // cores, M6 has three levels), so ask instead of assuming P + E.
        let levelCount = min(max(sysctlInt("hw.nperflevels"), 0), 8)
        let levels: [CoreCounts.Level] = (0..<levelCount).compactMap { index in
            let cores = sysctlInt("hw.perflevel\(index).physicalcpu")
            guard cores > 0 else { return nil }
            let name = sysctlString("hw.perflevel\(index).name")
            return CoreCounts.Level(name: name.isEmpty ? "Level \(index)" : name, cores: cores)
        }
        let physical = sysctlInt("hw.physicalcpu")
        return CoreCounts(levels: levels,
                          total: physical > 0 ? physical : levels.reduce(0) { $0 + $1.cores },
                          gpu: gpuCoreCount())
    }()

    private static func sysctlInt(_ name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : 0
    }

    /// `gpu-core-count` published by the GPU driver (AGXAccelerator), 0 when absent.
    private static func gpuCoreCount() -> Int {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"), &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }
        var count = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            if let value = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int {
                count = max(count, value)
            }
        }
        return count
    }
}
