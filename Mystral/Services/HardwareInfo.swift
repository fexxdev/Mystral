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

    /// 1 for M1 … 5 for M5, from the chip name ("M3 Pro" → 3); nil if unknown.
    static let chipFamily: Int? = family(fromChipName: chipName())

    static func family(fromChipName name: String) -> Int? {
        guard let m = name.firstIndex(of: "M") else { return nil }
        let digits = name[name.index(after: m)...].prefix { $0.isNumber }
        return Int(digits)
    }

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
        /// 0 when unknown.
        var performance: Int
        var efficiency: Int
        var total: Int
        var gpu: Int

        static let unknown = CoreCounts(performance: 0, efficiency: 0, total: 0, gpu: 0)
    }

    /// Read once: the hardware does not change while the app runs.
    static let coreCounts: CoreCounts = {
        let performance = sysctlInt("hw.perflevel0.physicalcpu")
        let efficiency = sysctlInt("hw.perflevel1.physicalcpu")
        let physical = sysctlInt("hw.physicalcpu")
        return CoreCounts(performance: performance, efficiency: efficiency,
                          total: physical > 0 ? physical : performance + efficiency,
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
