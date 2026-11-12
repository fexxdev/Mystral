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

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buffer, &size, nil, 0)
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func sysctlInt(_ name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        return result == 0 ? Int(value) : 0
    }

    static var physicalCpuCount: Int {
        let count = sysctlInt("hw.physicalcpu")
        return count > 0 ? count : ProcessInfo.processInfo.activeProcessorCount
    }

    static var performanceCoreCount: Int {
        sysctlInt("hw.perflevel0.physicalcpu")
    }

    static var efficiencyCoreCount: Int {
        sysctlInt("hw.perflevel1.physicalcpu")
    }

    static var gpuCoreCount: Int {
        var count = 0
        var iterator: io_iterator_t = 0
        let match = IOServiceMatching("AGXAccelerator")
        if IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == kIOReturnSuccess {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                if let prop = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
                    count = max(count, prop)
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        return count
    }

    /// Models where Apple firmware-locks SMC fan control on macOS Sequoia+.
    /// Source: github.com/crystalidea/macs-fan-control/issues/785 (M3/M4 Pro & Max MacBook Pros).
    private static let firmwareLockedModels: Set<String> = [
        "MacBookPro20,2", "MacBookPro20,3", "MacBookPro20,4",
        "MacBookPro20,5", "MacBookPro20,6", "MacBookPro20,7",
        "MacBookPro21,2", "MacBookPro21,3", "MacBookPro21,4", "MacBookPro21,5"
    ]

    static var isFirmwareLocked: Bool {
        firmwareLockedModels.contains(modelIdentifier())
    }
}

/// Reads individual CPU physical core die temperatures from IOHIDEventService.
/// Bound at runtime via dlopen so we never link private frameworks at build time.
final class IOHIDThermalReader: @unchecked Sendable {
    static let shared = IOHIDThermalReader()

    private typealias IOHIDEventSystemClientRef = OpaquePointer
    private typealias IOHIDServiceClientRef = OpaquePointer
    private typealias IOHIDEventRef = OpaquePointer

    private typealias F_IOHIDEventSystemClientCreate = @convention(c) (CFAllocator?) -> IOHIDEventSystemClientRef?
    private typealias F_IOHIDEventSystemClientSetMatching = @convention(c) (IOHIDEventSystemClientRef?, CFDictionary?) -> Int32
    private typealias F_IOHIDEventSystemClientCopyServices = @convention(c) (IOHIDEventSystemClientRef?) -> CFArray?
    private typealias F_IOHIDServiceClientCopyProperty = @convention(c) (IOHIDServiceClientRef?, CFString?) -> Unmanaged<CFTypeRef>?
    private typealias F_IOHIDServiceClientCopyEvent = @convention(c) (IOHIDServiceClientRef?, Int64, Int32, Int64) -> IOHIDEventRef?
    private typealias F_IOHIDEventGetFloatValue = @convention(c) (IOHIDEventRef?, Int64) -> Double

    private var client: IOHIDEventSystemClientRef?
    private var copyServices: F_IOHIDEventSystemClientCopyServices?
    private var copyProp: F_IOHIDServiceClientCopyProperty?
    private var copyEvent: F_IOHIDServiceClientCopyEvent?
    private var getFloat: F_IOHIDEventGetFloatValue?
    private let lock = NSLock()

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return nil }
        guard let create = unsafeBitCast(dlsym(handle, "IOHIDEventSystemClientCreate"), to: F_IOHIDEventSystemClientCreate?.self),
              let setMatching = unsafeBitCast(dlsym(handle, "IOHIDEventSystemClientSetMatching"), to: F_IOHIDEventSystemClientSetMatching?.self),
              let cs = unsafeBitCast(dlsym(handle, "IOHIDEventSystemClientCopyServices"), to: F_IOHIDEventSystemClientCopyServices?.self),
              let cp = unsafeBitCast(dlsym(handle, "IOHIDServiceClientCopyProperty"), to: F_IOHIDServiceClientCopyProperty?.self),
              let ce = unsafeBitCast(dlsym(handle, "IOHIDServiceClientCopyEvent"), to: F_IOHIDServiceClientCopyEvent?.self),
              let gf = unsafeBitCast(dlsym(handle, "IOHIDEventGetFloatValue"), to: F_IOHIDEventGetFloatValue?.self) else {
            return nil
        }
        guard let c = create(kCFAllocatorDefault) else { return nil }
        self.client = c
        self.copyServices = cs
        self.copyProp = cp
        self.copyEvent = ce
        self.getFloat = gf
        let matchingDict: [String: Any] = ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 0x05]
        _ = setMatching(c, matchingDict as CFDictionary)
    }

    /// Reads per-core die temperatures indexed from 1...expectedCount (matching "PMU tdie1"..."PMU tdieN").
    func readCpuDieTemps(expectedCount: Int) -> [Double?] {
        lock.lock()
        defer { lock.unlock() }

        guard let client = client, let copyServices = copyServices,
              let copyProp = copyProp, let copyEvent = copyEvent,
              let getFloat = getFloat, let services = copyServices(client) else { return [] }

        let count = CFArrayGetCount(services)
        var map: [Int: [Double]] = [:]

        for i in 0..<count {
            let service = unsafeBitCast(CFArrayGetValueAtIndex(services, i), to: IOHIDServiceClientRef.self)
            let nameRef = copyProp(service, "Product" as CFString)?.takeRetainedValue()
            guard let name = nameRef as? String, name.hasPrefix("PMU tdie") else { continue }
            let indexStr = name.dropFirst(8)
            guard let idx = Int(indexStr), idx >= 1 && idx <= expectedCount else { continue }
            if let event = copyEvent(service, 15, 0, 0) {
                let temp = getFloat(event, 15 << 16)
                if temp >= 20.0 && temp <= 125.0 {
                    map[idx, default: []].append(temp)
                }
            }
        }

        var results: [Double?] = []
        for idx in 1...expectedCount {
            if let vals = map[idx], !vals.isEmpty {
                results.append(vals.reduce(0, +) / Double(vals.count))
            } else {
                results.append(nil)
            }
        }
        return results
    }
}
