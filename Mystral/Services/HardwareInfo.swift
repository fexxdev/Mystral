import Foundation

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
        return String(cString: buffer)
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
