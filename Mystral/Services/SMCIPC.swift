import Foundation
import Darwin

/// Private, per-user IPC storage shared by the app and its privileged helper.
///
/// The helper receives this directory and its expected owner through launchd.
/// It refuses to start when either value is missing or the directory is unsafe.
enum SMCIPC {
    static let directoryEnvironmentKey = "MYSTRAL_IPC_DIRECTORY"
    static let uidEnvironmentKey = "MYSTRAL_IPC_UID"

    static var directoryPath: String {
        if let configured = ProcessInfo.processInfo.environment[directoryEnvironmentKey], !configured.isEmpty {
            return configured
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mystral", isDirectory: true)
            .appendingPathComponent("ipc", isDirectory: true)
            .path
    }

    static var dataPath: String { URL(fileURLWithPath: directoryPath).appendingPathComponent("smc-data.json").path }
    static var commandDirectoryPath: String { URL(fileURLWithPath: directoryPath).appendingPathComponent("commands", isDirectory: true).path }
    static var pidPath: String { URL(fileURLWithPath: directoryPath).appendingPathComponent("helper.pid").path }
    static var diagnosticPath: String { URL(fileURLWithPath: directoryPath).appendingPathComponent("diagnostics.log").path }

    static func prepareForApp() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: directoryPath, withIntermediateDirectories: true)
        guard chmod(directoryPath, 0o700) == 0 else { throw IPCError.permissionDenied(directoryPath) }

        try fm.createDirectory(atPath: commandDirectoryPath, withIntermediateDirectories: true)
        guard chmod(commandDirectoryPath, 0o700) == 0 else { throw IPCError.permissionDenied(commandDirectoryPath) }

        guard isSecureDirectory(path: directoryPath, expectedOwnerUID: getuid()),
              isSecureDirectory(path: commandDirectoryPath, expectedOwnerUID: getuid()) else {
            throw IPCError.insecureDirectory
        }
    }

    static func validateForHelper() -> Bool {
        guard let configuredPath = ProcessInfo.processInfo.environment[directoryEnvironmentKey],
              configuredPath == directoryPath,
              let uidString = ProcessInfo.processInfo.environment[uidEnvironmentKey],
              let expectedUID = UInt32(uidString) else {
            return false
        }
        return isSecureDirectory(path: directoryPath, expectedOwnerUID: expectedUID)
            && isSecureDirectory(path: commandDirectoryPath, expectedOwnerUID: expectedUID)
    }

    static func isSecureDirectory(path: String, expectedOwnerUID: UInt32) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard url.path == url.resolvingSymlinksInPath().path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              (attributes[.type] as? FileAttributeType) == .typeDirectory else {
            return false
        }

        let ownerUID = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777
        return ownerUID == expectedOwnerUID && (permissions & 0o077) == 0
    }

    enum IPCError: Error, LocalizedError {
        case insecureDirectory
        case permissionDenied(String)

        var errorDescription: String? {
            switch self {
            case .insecureDirectory:
                "Mystral IPC directory has unsafe ownership or permissions"
            case .permissionDenied(let path):
                "Cannot secure Mystral IPC path: \(path)"
            }
        }
    }
}
