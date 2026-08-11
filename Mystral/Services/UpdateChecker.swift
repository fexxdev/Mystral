import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "UpdateChecker")

@Observable
@MainActor
final class UpdateChecker {

    enum Status: Equatable {
        case unknown
        case checking
        case upToDate
        case updateAvailable(version: String, releaseURL: URL, dmgURL: URL?, notes: String)
        case downloading(version: String, progress: Double)
        case installing(version: String)
        case error(String)
    }

    private static let autoCheckKey = "updatesAutoCheckEnabled"
    private static let lastCheckedKey = "updatesLastCheckedAt"
    private static let releasesURL = URL(string: "https://api.github.com/repos/fexxdev/Mystral/releases/latest")!
    private static let minAutoCheckInterval: TimeInterval = 60 * 60 * 24

    var status: Status = .unknown
    var lastCheckedAt: Date?
    var autoCheckEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCheckEnabled, forKey: Self.autoCheckKey) }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private(set) var pendingUpdate: (version: String, releaseURL: URL, dmgURL: URL, notes: String)?
    private var downloadSession: DownloadSession?

    init() {
        if UserDefaults.standard.object(forKey: Self.autoCheckKey) != nil {
            self.autoCheckEnabled = UserDefaults.standard.bool(forKey: Self.autoCheckKey)
        } else {
            self.autoCheckEnabled = true
        }
        if let stored = UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Date {
            self.lastCheckedAt = stored
        }
    }

    // MARK: - Check for Updates

    func runAutoCheckIfNeeded() {
        guard autoCheckEnabled else { return }
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < Self.minAutoCheckInterval {
            return
        }
        Task { await checkForUpdates(silent: true) }
    }

    func checkForUpdates(silent: Bool = false) async {
        if !silent { status = .checking }
        do {
            var request = URLRequest(url: Self.releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Mystral/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tag_name.hasPrefix("v")
                ? String(release.tag_name.dropFirst())
                : release.tag_name

            lastCheckedAt = Date()
            UserDefaults.standard.set(lastCheckedAt, forKey: Self.lastCheckedKey)

            if Self.compareVersions(latestVersion, currentVersion) == .orderedDescending {
                let dmgURL = release.assets.first(where: { $0.name.hasSuffix(".dmg") })
                    .flatMap { URL(string: $0.browser_download_url) }
                    .flatMap { Self.isTrustedReleaseURL($0) ? $0 : nil }
                let pageURL = URL(string: release.html_url) ?? Self.releasesURL
                status = .updateAvailable(version: latestVersion, releaseURL: pageURL, dmgURL: dmgURL, notes: release.body ?? "")
                logger.info("Update available: \(latestVersion, privacy: .public)")
            } else {
                status = .upToDate
                logger.info("Up to date (current \(self.currentVersion, privacy: .public), latest \(latestVersion, privacy: .public))")
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            if !silent {
                status = .error(error.localizedDescription)
            }
        }
    }

    func openReleasePage() {
        if case .updateAvailable(_, let url, _, _) = status {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/fexxdev/Mystral/releases")!)
        }
    }

    // MARK: - Install Update

    func installUpdate() async {
        guard case .updateAvailable(let version, let releaseURL, let dmgURL?, let notes) = status else { return }
        pendingUpdate = (version, releaseURL, dmgURL, notes)

        do {
            let dmgPath = try await downloadDMG(url: dmgURL, version: version)

            status = .installing(version: version)

            let mountPoint = try mountDMG(at: dmgPath)
            do {
                try replaceApp(from: mountPoint)
            } catch {
                unmountDMG(mountPoint: mountPoint)
                try? FileManager.default.removeItem(atPath: mountPoint)
                try? FileManager.default.removeItem(at: dmgPath)
                throw error
            }

            unmountDMG(mountPoint: mountPoint)
            try? FileManager.default.removeItem(atPath: mountPoint)
            try? FileManager.default.removeItem(at: dmgPath)

            pendingUpdate = nil
            relaunchAndTerminate()
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError {
            restorePendingStatus()
        } catch is CancellationError {
            restorePendingStatus()
        } catch {
            logger.error("Install failed: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
        }
    }

    func cancelInstall() {
        downloadSession?.cancel()
        downloadSession = nil
        restorePendingStatus()
    }

    func retryInstall() {
        restorePendingStatus()
    }

    private func restorePendingStatus() {
        if let p = pendingUpdate {
            status = .updateAvailable(version: p.version, releaseURL: p.releaseURL, dmgURL: p.dmgURL, notes: p.notes)
        } else {
            status = .unknown
        }
    }

    // MARK: - Download

    private func downloadDMG(url: URL, version: String) async throws -> URL {
        guard Self.isTrustedReleaseURL(url) else { throw UpdateError.untrustedURL }
        status = .downloading(version: version, progress: 0)

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mystral-update-\(UUID().uuidString).dmg")
        try? FileManager.default.removeItem(at: dest)

        return try await withCheckedThrowingContinuation { continuation in
            let session = DownloadSession(
                url: url,
                destination: dest,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.status = .downloading(version: version, progress: progress)
                    }
                },
                onComplete: { result in
                    continuation.resume(with: result)
                }
            )
            self.downloadSession = session
            session.start()
        }
    }

    // MARK: - Mount / Unmount

    private func mountDMG(at path: URL) throws -> String {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mystral-update-mount-\(UUID().uuidString)", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: false)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", path.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw UpdateError.mountFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return mountPoint
    }

    private func unmountDMG(mountPoint: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint, "-force"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Replace App

    private func replaceApp(from mountPoint: String) throws {
        let appPath = Bundle.main.bundlePath
        let appName = (appPath as NSString).lastPathComponent
        var sourcePath = "\(mountPoint)/\(appName)"
        let backupPath = appPath + ".old"

        if !FileManager.default.fileExists(atPath: sourcePath) {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: mountPoint)) ?? []
            guard let found = contents.first(where: { $0.hasSuffix(".app") }) else {
                throw UpdateError.appNotFoundInDMG
            }
            sourcePath = "\(mountPoint)/\(found)"
        }

        guard Self.isValidBundleMetadata(at: sourcePath, currentVersion: currentVersion) else {
            throw UpdateError.invalidBundleMetadata
        }
        try Self.verifyCodeSignature(at: sourcePath)

        let parentDir = (appPath as NSString).deletingLastPathComponent
        let fm = FileManager.default

        if fm.isWritableFile(atPath: parentDir) {
            try? fm.removeItem(atPath: backupPath)
            try fm.moveItem(atPath: appPath, toPath: backupPath)
            do {
                try fm.copyItem(atPath: sourcePath, toPath: appPath)
            } catch {
                try? fm.moveItem(atPath: backupPath, toPath: appPath)
                throw error
            }
            removeQuarantine(at: appPath)
            try? fm.removeItem(atPath: backupPath)
        } else {
            try replaceAppElevated(appPath: appPath, sourcePath: sourcePath, backupPath: backupPath)
        }
    }

    private func replaceAppElevated(appPath: String, sourcePath: String, backupPath: String) throws {
        let esc: (String) -> String = { $0.replacingOccurrences(of: "'", with: "'\\''") }
        let cmd = [
            "rm -rf '\(esc(backupPath))'",
            "mv '\(esc(appPath))' '\(esc(backupPath))'",
            "cp -R '\(esc(sourcePath))' '\(esc(appPath))'",
            "xattr -rd com.apple.quarantine '\(esc(appPath))'",
            "rm -rf '\(esc(backupPath))'",
        ].joined(separator: " && ")
        let script = "do shell script \"\(cmd)\" with administrator privileges"

        guard let appleScript = NSAppleScript(source: script) else {
            throw UpdateError.replaceFailed("Failed to create AppleScript")
        }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? -1
            if code == -128 { throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError) }
            throw UpdateError.replaceFailed(
                (error[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
            )
        }
    }

    // MARK: - Relaunch

    private func relaunchAndTerminate() {
        let appPath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let escaped = appPath.replacingOccurrences(of: "'", with: "'\\''")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open '\(escaped)'"]
        try? process.run()

        logger.info("Relaunch script spawned, terminating for update")
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func removeQuarantine(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-rd", "com.apple.quarantine", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    nonisolated static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let aParts = a.split(separator: ".").compactMap { Int($0.prefix(while: \.isNumber)) }
        let bParts = b.split(separator: ".").compactMap { Int($0.prefix(while: \.isNumber)) }
        let count = max(aParts.count, bParts.count)
        for i in 0..<count {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return .orderedSame
    }

    nonisolated static func isTrustedReleaseURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com",
              url.path.hasPrefix("/fexxdev/Mystral/releases/download/"),
              url.pathExtension.lowercased() == "dmg" else { return false }
        return true
    }

    nonisolated static func hasDeveloperIDSignature(_ output: String) -> Bool {
        output.contains("Authority=Developer ID Application:") && output.contains("TeamIdentifier=")
    }

    nonisolated static func isValidBundleMetadata(at appPath: String, currentVersion: String) -> Bool {
        let infoPath = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist").path
        guard let info = NSDictionary(contentsOfFile: infoPath),
              info["CFBundleIdentifier"] as? String == "com.fexxdev.Mystral",
              info["CFBundlePackageType"] as? String == "APPL",
              let version = info["CFBundleShortVersionString"] as? String else { return false }
        return compareVersions(version, currentVersion) == .orderedDescending
    }

    nonisolated static func verifyCodeSignature(at appPath: String) throws {
        let verification = try runCodesign(arguments: ["--verify", "--deep", "--strict", "--verbose=2", appPath])
        guard verification.status == 0 else { throw UpdateError.signatureInvalid }

        let details = try runCodesign(arguments: ["-dv", "--verbose=4", appPath])
        guard details.status == 0, hasDeveloperIDSignature(details.output) else {
            throw UpdateError.signatureInvalid
        }
    }

    private nonisolated static func runCodesign(arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, text)
    }

    // MARK: - Types

    private enum UpdateError: LocalizedError {
        case badResponse(Int)
        case mountFailed(String)
        case appNotFoundInDMG
        case replaceFailed(String)
        case versionMismatch
        case untrustedURL
        case invalidBundleMetadata
        case signatureInvalid

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): "GitHub returned status \(code)"
            case .mountFailed(let msg): "Failed to mount DMG: \(msg)"
            case .appNotFoundInDMG: "Mystral.app not found in the downloaded DMG"
            case .replaceFailed(let msg): "Failed to replace app: \(msg)"
            case .versionMismatch: "Downloaded version is not newer than current"
            case .untrustedURL: "Update download URL is not a trusted Mystral GitHub release"
            case .invalidBundleMetadata: "Downloaded app metadata is not a valid newer Mystral release"
            case .signatureInvalid: "Downloaded app has no valid Developer ID signature"
            }
        }
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }
}

// MARK: - Download Session

private final class DownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private let onComplete: @Sendable (Result<URL, Error>) -> Void
    private var completed = false

    init(url: URL, destination: URL,
         onProgress: @escaping @Sendable (Double) -> Void,
         onComplete: @escaping @Sendable (Result<URL, Error>) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        self.onComplete = onComplete
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.task = self.session?.downloadTask(with: url)
    }

    func start() { task?.resume() }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard !completed else { return }
        completed = true
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            onComplete(.failure(NSError(domain: "Mystral.Update", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Update download returned an invalid HTTP response"])))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            onComplete(.success(destination))
        } catch {
            onComplete(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed, let error else { return }
        completed = true
        onComplete(.failure(error))
    }
}
