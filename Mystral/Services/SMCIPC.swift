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

    static var dataPath: String { URL(fileURLWithPath: directoryPath).appendingPathComponent(dataFileName).path }
    static var commandDirectoryPath: String { URL(fileURLWithPath: directoryPath).appendingPathComponent("commands", isDirectory: true).path }
    static var pidPath: String { URL(fileURLWithPath: directoryPath).appendingPathComponent(pidFileName).path }
    static var diagnosticPath: String { URL(fileURLWithPath: directoryPath).appendingPathComponent(diagnosticFileName).path }

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

    static let dataFileName = "smc-data.json"
    static let pidFileName = "helper.pid"
    static let diagnosticFileName = "diagnostics.log"
    static let legacyHelperLogNames = ["helper-stdout.log", "helper-stderr.log"]

    /// Opens the IPC directory for the root helper, or nil when the launchd
    /// configuration is missing or the directory is unsafe.
    static func openForHelper() -> HelperIPCDirectory? {
        guard let configuredPath = ProcessInfo.processInfo.environment[directoryEnvironmentKey],
              configuredPath == directoryPath,
              let uidString = ProcessInfo.processInfo.environment[uidEnvironmentKey],
              let expectedUID = UInt32(uidString) else {
            return nil
        }
        return HelperIPCDirectory(path: directoryPath, expectedOwnerUID: expectedUID)
    }

    /// Deletes the launchd log files older plists made root write into the IPC directory.
    static func removeLegacyHelperLogs() {
        for name in legacyHelperLogNames {
            _ = unlink(URL(fileURLWithPath: directoryPath).appendingPathComponent(name).path)
        }
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

    static func isSecureDirectory(descriptor: Int32, expectedOwnerUID: UInt32) -> Bool {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFDIR
            && info.st_uid == expectedOwnerUID
            && (info.st_mode & 0o077) == 0
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

/// Root-side handle on the user-owned IPC directory.
///
/// Ownership and mode are checked on the open descriptors, and every file operation is
/// relative to them with O_NOFOLLOW, so swapping a path for a symlink cannot redirect root I/O.
final class HelperIPCDirectory {
    static let maxCommandBytes = 4096

    private let directoryFD: Int32
    private let commandsFD: Int32
    private let expectedOwnerUID: UInt32

    init?(path: String, expectedOwnerUID: UInt32) {
        let directoryFD = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { return nil }
        guard SMCIPC.isSecureDirectory(descriptor: directoryFD, expectedOwnerUID: expectedOwnerUID) else {
            close(directoryFD)
            return nil
        }
        let commandsFD = openat(directoryFD, "commands", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard commandsFD >= 0 else {
            close(directoryFD)
            return nil
        }
        guard SMCIPC.isSecureDirectory(descriptor: commandsFD, expectedOwnerUID: expectedOwnerUID) else {
            close(commandsFD)
            close(directoryFD)
            return nil
        }
        self.directoryFD = directoryFD
        self.commandsFD = commandsFD
        self.expectedOwnerUID = expectedOwnerUID
    }

    deinit {
        close(commandsFD)
        close(directoryFD)
    }

    /// Writes through a fresh O_EXCL temp file and renameat, which replaces a planted
    /// symlink instead of following it.
    @discardableResult
    func writeAtomically(_ data: Data, named name: String) -> Bool {
        guard Self.isPlainName(name) else { return false }
        let temporaryName = ".\(name).\(UUID().uuidString).tmp"
        let fd = openat(directoryFD, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return false }
        let written = Self.writeAll(data, to: fd) && fchmod(fd, 0o644) == 0
        close(fd)
        guard written, renameat(directoryFD, temporaryName, directoryFD, name) == 0 else {
            unlinkat(directoryFD, temporaryName, 0)
            return false
        }
        return true
    }

    func removeFile(named name: String) {
        guard Self.isPlainName(name) else { return }
        unlinkat(directoryFD, name, 0)
    }

    func commandFileNames() -> [String] {
        let listingFD = dup(commandsFD)
        guard listingFD >= 0, let directory = fdopendir(listingFD) else {
            if listingFD >= 0 { close(listingFD) }
            return []
        }
        defer { closedir(directory) }
        rewinddir(directory)
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if name.hasSuffix(".json"), Self.isPlainName(name) { names.append(name) }
        }
        return names.sorted()
    }

    /// Returns the command bytes only for a small regular file owned by the session user
    /// and not writable by group or others.
    func readCommand(named name: String) -> Data? {
        guard Self.isPlainName(name) else { return nil }
        let fd = openat(commandsFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == expectedOwnerUID,
              (info.st_mode & 0o022) == 0,
              info.st_size >= 0, info.st_size <= Self.maxCommandBytes else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: Self.maxCommandBytes + 1)
        let count = read(fd, &buffer, buffer.count)
        guard count >= 0, count <= Self.maxCommandBytes else { return nil }
        return Data(buffer[0..<count])
    }

    func removeCommand(named name: String) {
        guard Self.isPlainName(name) else { return }
        unlinkat(commandsFD, name, 0)
    }

    func purgeCommands() {
        commandFileNames().forEach(removeCommand(named:))
    }

    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    private static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                pointer += written
                remaining -= written
            }
            return true
        }
    }
}
