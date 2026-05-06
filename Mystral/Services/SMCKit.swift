import Foundation
import IOKit

enum SMCError: Error, LocalizedError {
    case driverNotFound
    case failedToOpen
    case keyNotFound(String)
    case readError(kern_return_t)
    case writeError(kern_return_t)
    case unsupportedDataType(String)

    var errorDescription: String? {
        switch self {
        case .driverNotFound: "AppleSMC driver not found"
        case .failedToOpen: "Failed to open SMC connection"
        case .keyNotFound(let key): "SMC key not found: \(key)"
        case .readError(let code): "SMC read error: \(code)"
        case .writeError(let code): "SMC write error: \(code)"
        case .unsupportedDataType(let type): "Unsupported SMC data type: \(type)"
        }
    }
}

final class SMCKit: @unchecked Sendable {
    private var connection: io_connect_t = 0
    private let lock = NSLock()

    private static let smcHandlerSelector: UInt32 = 2
    private static let cmdReadBytes: UInt8 = 5
    private static let cmdWriteBytes: UInt8 = 6
    private static let cmdReadIndex: UInt8 = 8
    private static let cmdReadKeyInfo: UInt8 = 9

    struct DataType {
        static let flt = dataTypeToUInt32("flt ")
        static let sp78 = dataTypeToUInt32("sp78")
        static let fpe2 = dataTypeToUInt32("fpe2")
        static let ui8 = dataTypeToUInt32("ui8 ")
        static let ui16 = dataTypeToUInt32("ui16")
        static let ui32 = dataTypeToUInt32("ui32")
        static let flag = dataTypeToUInt32("flag")
    }

    // Kernel structures - must match AppleSMC driver exactly
    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCKeyData {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    func open() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { throw SMCError.driverNotFound }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        guard result == kIOReturnSuccess else { throw SMCError.failedToOpen }
    }

    func close() {
        if connection != 0 { IOServiceClose(connection); connection = 0 }
    }

    deinit { close() }

    static func fourCharCode(_ key: String) -> UInt32 {
        var result: UInt32 = 0
        for char in key.utf8.prefix(4) { result = (result << 8) | UInt32(char) }
        return result
    }

    static func fourCharString(_ code: UInt32) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
                     UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    private static func dataTypeToUInt32(_ type: String) -> UInt32 { fourCharCode(type) }

    private func callSMC(_ input: inout SMCKeyData) throws -> SMCKeyData {
        lock.lock()
        defer { lock.unlock() }
        var output = SMCKeyData()
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(connection, Self.smcHandlerSelector,
                                                &input, inputSize, &output, &outputSize)
        guard result == kIOReturnSuccess else { throw SMCError.readError(result) }
        return output
    }

    private var keyInfoCache: [UInt32: SMCKeyInfoData] = [:]

    private func readKeyInfo(key: UInt32) throws -> SMCKeyInfoData {
        if let cached = keyInfoCache[key] { return cached }
        var input = SMCKeyData()
        input.key = key
        input.data8 = Self.cmdReadKeyInfo
        let info = try callSMC(&input).keyInfo
        keyInfoCache[key] = info
        return info
    }

    func readRawBytes(key: String) throws -> (bytes: [UInt8], dataType: UInt32, dataSize: UInt32) {
        let keyCode = Self.fourCharCode(key)
        let info = try readKeyInfo(key: keyCode)
        var input = SMCKeyData()
        input.key = keyCode
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Self.cmdReadBytes
        var output = try callSMC(&input)
        let size = Int(info.dataSize)
        let bytes: [UInt8] = withUnsafeBytes(of: &output.bytes) { ptr in
            Array(ptr.prefix(size))
        }
        return (bytes, info.dataType, info.dataSize)
    }

    func readFloat(key: String) throws -> Double {
        let (bytes, dataType, _) = try readRawBytes(key: key)
        switch dataType {
        case DataType.flt:
            guard bytes.count >= 4 else { return 0 }
            var value: Float = 0
            withUnsafeMutableBytes(of: &value) { ptr in
                for i in 0..<4 { ptr[i] = bytes[i] }
            }
            return Double(value)
        case DataType.sp78:
            guard bytes.count >= 2 else { return 0 }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256.0
        case DataType.fpe2:
            guard bytes.count >= 2 else { return 0 }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4.0
        case DataType.ui8:
            return Double(bytes[0])
        case DataType.ui16:
            guard bytes.count >= 2 else { return 0 }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case DataType.ui32:
            guard bytes.count >= 4 else { return 0 }
            let value = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            return Double(value)
        case DataType.flag:
            return Double(bytes[0])
        case 0:
            throw SMCError.keyNotFound(key)
        default:
            throw SMCError.unsupportedDataType(Self.fourCharString(dataType))
        }
    }

    func readInteger(key: String) throws -> Int { Int(try readFloat(key: key)) }

    func writeBytes(key: String, dataType: UInt32, bytes: [UInt8]) throws {
        let code = try tryWriteBytes(key: key, dataType: dataType, bytes: bytes)
        if code != 0 { throw SMCError.writeError(kern_return_t(code)) }
    }

    @discardableResult
    func tryWriteBytes(key: String, dataType: UInt32, bytes: [UInt8]) throws -> UInt8 {
        let keyCode = Self.fourCharCode(key)
        let info = try readKeyInfo(key: keyCode)
        guard info.dataSize > 0 else { return 0x84 }
        var input = SMCKeyData()
        input.key = keyCode
        input.data8 = Self.cmdWriteBytes
        input.keyInfo = info
        var tupleBytes = input.bytes
        withUnsafeMutableBytes(of: &tupleBytes) { ptr in
            for (i, byte) in bytes.prefix(Int(info.dataSize)).enumerated() { ptr[i] = byte }
        }
        input.bytes = tupleBytes
        let result = try callSMC(&input)
        return result.result
    }

    @discardableResult
    func tryWriteUInt8(key: String, value: UInt8) throws -> UInt8 {
        try tryWriteBytes(key: key, dataType: DataType.ui8, bytes: [value])
    }

    @discardableResult
    func tryWriteFloat(key: String, value: Double) throws -> UInt8 {
        var floatVal = Float(value)
        let bytes: [UInt8] = withUnsafeBytes(of: &floatVal) { Array($0) }
        return try tryWriteBytes(key: key, dataType: DataType.flt, bytes: bytes)
    }

    func keyExists(_ key: String) -> Bool {
        let keyCode = Self.fourCharCode(key)
        guard let info = try? readKeyInfo(key: keyCode) else { return false }
        return info.dataSize > 0 && info.dataType != 0
    }

    func writeRaw(key: String, dataType: UInt32, dataSize: UInt32, bytes: [UInt8]) throws {
        let keyCode = Self.fourCharCode(key)
        var input = SMCKeyData()
        input.key = keyCode
        input.data8 = Self.cmdWriteBytes
        input.keyInfo.dataSize = dataSize
        input.keyInfo.dataType = dataType
        var tupleBytes = input.bytes
        withUnsafeMutableBytes(of: &tupleBytes) { ptr in
            for (i, byte) in bytes.prefix(Int(dataSize)).enumerated() { ptr[i] = byte }
        }
        input.bytes = tupleBytes
        let result = try callSMC(&input)
        if result.result != 0 { throw SMCError.writeError(kern_return_t(result.result)) }
    }

    func writeFpe2(key: String, value: Double) throws {
        let raw = UInt16(max(0, min(value * 4.0, Double(UInt16.max))))
        try writeBytes(key: key, dataType: DataType.fpe2, bytes: [UInt8(raw >> 8), UInt8(raw & 0xFF)])
    }

    func writeFloat(key: String, value: Double) throws {
        var floatVal = Float(value)
        let bytes: [UInt8] = withUnsafeBytes(of: &floatVal) { Array($0) }
        try writeBytes(key: key, dataType: DataType.flt, bytes: bytes)
    }

    func writeUInt8(key: String, value: UInt8) throws {
        try writeBytes(key: key, dataType: DataType.ui8, bytes: [value])
    }

    func keyCount() throws -> Int { try readInteger(key: "#KEY") }

    func keyAtIndex(_ index: Int) throws -> String {
        var input = SMCKeyData()
        input.data8 = Self.cmdReadIndex
        input.data32 = UInt32(index)
        let output = try callSMC(&input)
        return Self.fourCharString(output.key)
    }

    private var cachedAllKeys: [String]?
    private var cachedTemperatureKeys: [String]?

    func invalidateCaches() {
        cachedAllKeys = nil
        cachedTemperatureKeys = nil
        keyInfoCache.removeAll()
    }

    func allKeys() throws -> [String] {
        if let cached = cachedAllKeys { return cached }
        let count = try keyCount()
        let keys = try (0..<count).map { try keyAtIndex($0) }
        cachedAllKeys = keys
        return keys
    }

    func temperatureKeys() throws -> [String] {
        if let cached = cachedTemperatureKeys { return cached }
        let keys = try allKeys().filter { $0.hasPrefix("T") }
        cachedTemperatureKeys = keys
        return keys
    }
}
