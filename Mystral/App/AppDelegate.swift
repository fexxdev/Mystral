import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    var menuBarManager: MenuBarManager?
    var fanController: FanController?
    var profileManager: ProfileManager?
    var autoSwitcher: ProfileAutoSwitcher?
    var alertManager: AlertManager?
    var updateChecker: UpdateChecker?
    private var smcProxy: SMCProxyService?
    private var activityToken: NSObjectProtocol?
    private var helperLaunchFailures = 0
    private static let maxHelperLaunchAttempts = 3
    private var helperGaveUpAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching — start")
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            logger.info("Running under XCTest — skipping init")
            return
        }

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .suddenTerminationDisabled],
            reason: "Active fan monitoring and control"
        )
        logger.info("App Nap prevention token acquired")

        profileManager = ProfileManager()

        let smcService: SMCServiceProtocol
        if getuid() == 0 {
            do {
                smcService = try SMCService()
                logger.info("Running as root — direct SMC access")
            } catch {
                logger.error("SMC init failed as root: \(error.localizedDescription, privacy: .public)")
                smcService = FallbackSMCService()
            }
        } else {
            logger.info("Running as user — using SMCProxyService")
            do {
                try SMCIPC.prepareForApp()
            } catch {
                logger.error("Cannot secure helper IPC directory: \(error.localizedDescription, privacy: .public)")
            }
            let proxy = SMCProxyService()
            smcProxy = proxy
            smcService = proxy
            ensureHelperInstalled()
        }

        fanController = FanController(smcService: smcService, profileManager: profileManager!)
        fanController!.helperRestarter = { [weak self] in
            self?.ensureHelperInstalled()
        }
        fanController!.manualHelperRestarter = { [weak self] in
            self?.forceRelaunchHelper()
        }
        if UserDefaults.standard.object(forKey: "smoothingEnabled") != nil {
            fanController!.smoothingEnabled = UserDefaults.standard.bool(forKey: "smoothingEnabled")
        }
        let alpha = UserDefaults.standard.double(forKey: "smoothingAlpha")
        if alpha > 0 { fanController!.smoothingAlpha = alpha }
        if UserDefaults.standard.object(forKey: "deadbandPercent") != nil {
            fanController!.deadbandPercent = UserDefaults.standard.double(forKey: "deadbandPercent")
        }
        if UserDefaults.standard.object(forKey: "minimumFanPercentage") != nil {
            fanController!.minimumFanPercentage = UserDefaults.standard.double(forKey: "minimumFanPercentage")
        }
        if UserDefaults.standard.object(forKey: "aggressiveOverrideEnabled") != nil {
            fanController!.aggressiveOverrideEnabled = UserDefaults.standard.bool(forKey: "aggressiveOverrideEnabled")
        }
        let interval = UserDefaults.standard.double(forKey: "pollingInterval")
        if interval > 0 { fanController!.pollingInterval = interval }
        autoSwitcher = ProfileAutoSwitcher(profileManager: profileManager!)
        alertManager = AlertManager()
        fanController!.alertManager = alertManager
        alertManager!.requestPermissionIfNeeded()
        logger.info("Creating MenuBarManager — fanController=\(self.fanController == nil ? "nil" : "exists", privacy: .public)")
        menuBarManager = MenuBarManager(
            fanController: fanController!,
            profileManager: profileManager!,
            onOpenWindow: { [weak self] in self?.openMainWindow() }
        )
        logger.info("MenuBarManager created — menuBarManager=\(self.menuBarManager == nil ? "nil" : "exists", privacy: .public)")
        fanController!.start()
        autoSwitcher!.start()

        updateChecker = UpdateChecker()
        updateChecker!.runAutoCheckIfNeeded()
        logger.info("applicationDidFinishLaunching — complete")
    }

    func forceRelaunchHelper() {
        logger.info("Manual helper restart requested")
        helperLaunchFailures = 0
        helperGaveUpAt = nil
        guard smcProxy != nil, let execPath = Bundle.main.executablePath else { return }
        if HelperDaemon.isInstalled(forExecutable: execPath, helperVersion: SMCHelperMode.helperRevision) {
            // Prompt-free: ask the running helper to recycle; the launchd daemon's
            // KeepAlive relaunches the root-owned helper immediately.
            smcProxy?.requestRestart()
        } else {
            ensureHelperInstalled()
        }
    }

    /// Ensures the privileged SMC helper is installed as a root-owned launchd daemon.
    /// The first install and each helper build update require administrator approval.
    private func ensureHelperInstalled() {
        guard smcProxy != nil, let execPath = Bundle.main.executablePath else { return }

        if HelperDaemon.isInstalled(forExecutable: execPath, helperVersion: SMCHelperMode.helperRevision) {
            helperLaunchFailures = 0
            return
        }

        if helperLaunchFailures >= Self.maxHelperLaunchAttempts {
            if let gaveUp = helperGaveUpAt, Date().timeIntervalSince(gaveUp) > 12 * 3600 {
                logger.info("12 hours since helper install gave up — resetting for retry")
                helperLaunchFailures = 0
                helperGaveUpAt = nil
            } else {
                if helperGaveUpAt == nil { helperGaveUpAt = Date() }
                logger.warning("Helper install suppressed — \(self.helperLaunchFailures) consecutive failures, retrying in 12h or on manual restart")
                return
            }
        }

        Task.detached {
            let ok = HelperDaemon.install(
                executablePath: execPath,
                helperVersion: SMCHelperMode.helperRevision
            )
            await MainActor.run {
                if ok {
                    self.helperLaunchFailures = 0
                    logger.info("Helper daemon installed and running")
                } else {
                    self.helperLaunchFailures += 1
                    logger.error("Helper daemon install failed (attempt \(self.helperLaunchFailures)/\(Self.maxHelperLaunchAttempts, privacy: .public))")
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Leave the helper running — it's a launchd daemon now and is meant to persist.
        // fanController.stop() writes the un-force command, which the still-alive helper
        // applies on its next tick, returning fans to auto control.
        logger.info("applicationWillTerminate — restoring auto mode (helper daemon persists)")
        fanController?.stop()
    }

    func openMainWindow() {
        logger.info("openMainWindow — existing window=\(self.window != nil, privacy: .public)")
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            return
        }

        let contentView = MainView(
            fanController: fanController!,
            profileManager: profileManager!,
            alertManager: alertManager,
            autoSwitcher: autoSwitcher,
            updateChecker: updateChecker
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = NSSize(width: 1200, height: 640)
        window.title = "Mystral"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.setFrameAutosaveName("MystralMainWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        self.window = window
        logger.info("openMainWindow — new window created and shown")
    }

    func windowWillClose(_ notification: Notification) {
        logger.info("windowWillClose — switching to accessory mode")
        NSApp.setActivationPolicy(.accessory)
    }
}

final class FallbackSMCService: SMCServiceProtocol, @unchecked Sendable {
    func getAllSensors() throws -> [Sensor] { [] }
    func readTemperature(key: String) throws -> Double { 0 }
    func getAllFans() throws -> [Fan] { [] }
    func readFanSpeed(index: Int) throws -> Int { 0 }
    func setFanSpeed(index: Int, percentage: Double) throws {}
    func setFanMode(index: Int, mode: FanMode) throws {}
    func setForcedMode(fanCount: Int, forced: Bool) throws {}
    func heartbeat() throws {}
}

/// Installs and tracks the privileged SMC helper as a launchd LaunchDaemon.
///
/// Previously the helper was spawned as a root *orphan* via `osascript … with
/// administrator privileges` and backgrounded. launchd (pid 1) adopts such orphans
/// and reaps them during housekeeping (~every 20–40 min), forcing a fresh admin
/// prompt each time. The managed LaunchDaemon now runs a root-owned copy from
/// `/Library/PrivilegedHelperTools` and revives it in <1s on any death.
enum HelperDaemon {
    static let label = "com.fexxdev.Mystral.helper"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    static let helperToolPath = "/Library/PrivilegedHelperTools/\(label)"
    static let installationFileCheckCommand = "/bin/test"
    private static let sourceEnvironmentKey = "MYSTRAL_HELPER_SOURCE"

    /// True if the daemon and its root-owned helper tool match the current app build.
    static func isInstalled(
        forExecutable executablePath: String,
        ipcDirectoryPath: String = SMCIPC.directoryPath,
        appVersion: String = SMCHelperMode.appVersion,
        helperVersion: String = SMCHelperMode.helperRevision
    ) -> Bool {
        guard isAllowedExecutablePath(executablePath),
              isSecureHelperTool(),
              FileManager.default.fileExists(atPath: plistPath),
              isLaunchdJobLoaded() else { return false }
        guard let dict = NSDictionary(contentsOfFile: plistPath),
              let args = dict["ProgramArguments"] as? [String],
              let program = args.first,
              let environment = dict["EnvironmentVariables"] as? [String: String] else { return false }
        return program == helperToolPath
            && args.dropFirst().first == "--smc-helper"
            && environment[SMCIPC.directoryEnvironmentKey] == ipcDirectoryPath
            && environment[SMCIPC.uidEnvironmentKey] == String(getuid())
            && environment[sourceEnvironmentKey] == executablePath
            && environment[SMCHelperMode.helperVersionEnvironmentKey] == appVersion
            && environment[SMCHelperMode.helperRevisionEnvironmentKey] == helperVersion
    }

    /// Installs or repairs the root-owned helper and daemon. It prompts for an
    /// administrator password on first install and when the helper build changes.
    @discardableResult
    static func install(
        executablePath: String,
        ipcDirectoryPath: String = SMCIPC.directoryPath,
        appVersion: String = SMCHelperMode.appVersion,
        helperVersion: String = SMCHelperMode.helperRevision
    ) -> Bool {
        guard isAllowedExecutablePath(executablePath),
              SMCIPC.isSecureDirectory(path: ipcDirectoryPath, expectedOwnerUID: getuid()),
              SMCIPC.isSecureDirectory(path: URL(fileURLWithPath: ipcDirectoryPath).appendingPathComponent("commands").path, expectedOwnerUID: getuid()) else {
            logger.error("Refusing helper install: executable or IPC directory is not trusted")
            return false
        }

        let plist = plistContents(
            sourceExecutablePath: executablePath,
            ipcDirectoryPath: ipcDirectoryPath,
            appVersion: appVersion,
            helperVersion: helperVersion
        )
        let encoded = Data(plist.utf8).base64EncodedString()
        let installCommands = [
            "/bin/mkdir -p /Library/PrivilegedHelperTools",
            "/usr/sbin/chown root:wheel /Library/PrivilegedHelperTools",
            "/bin/chmod 755 /Library/PrivilegedHelperTools",
            "/usr/bin/install -o root -g wheel -m 755 \(shellQuote(executablePath)) \(shellQuote(helperToolPath))",
            "/bin/launchctl bootout system/\(label) 2>/dev/null || true",
            "/usr/bin/printf '%s' \(shellQuote(encoded)) | /usr/bin/base64 -D > \(shellQuote(plistPath))",
            "\(installationFileCheckCommand) -s \(shellQuote(plistPath))",
            "/usr/sbin/chown root:wheel \(shellQuote(plistPath))",
            "/bin/chmod 644 \(shellQuote(plistPath))"
        ] + launchdLifecycleCommands()
        let installScript = installCommands.joined(separator: " && ")
        let appleScriptQuote: (String) -> String = { value in
            "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        let osa = "do shell script \(appleScriptQuote(installScript)) with administrator privileges"
        guard let script = NSAppleScript(source: osa) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? -1
            logger.error("Daemon install failed (code=\(code, privacy: .public)): \(error, privacy: .public)")
            return false
        }
        return isInstalled(
            forExecutable: executablePath,
            ipcDirectoryPath: ipcDirectoryPath,
            appVersion: appVersion,
            helperVersion: helperVersion
        )
    }

    static func launchdLifecycleCommands(plistPath: String = HelperDaemon.plistPath) -> [String] {
        let quotedPlistPath = shellQuote(plistPath)
        return [
            "/bin/launchctl bootstrap system \(quotedPlistPath)",
            "/bin/launchctl enable system/\(label)",
            "/bin/launchctl kickstart -k system/\(label)",
            "/bin/launchctl print system/\(label) >/dev/null"
        ]
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func isLaunchdJobLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func isSecureHelperTool() -> Bool {
        let url = URL(fileURLWithPath: helperToolPath)
        guard url.path == url.resolvingSymlinksInPath().path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: helperToolPath),
              (attributes[.type] as? FileAttributeType) == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0 else {
            return false
        }
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777
        return (permissions & 0o022) == 0
    }

    static func isAllowedExecutablePath(_ executablePath: String) -> Bool {
        let url = URL(fileURLWithPath: executablePath)
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.path == url.standardizedFileURL.path,
              resolved.path.hasPrefix("/Applications/"),
              resolved.path.contains("/Contents/MacOS/"),
              let applicationsAttributes = try? FileManager.default.attributesOfItem(atPath: "/Applications"),
              (applicationsAttributes[.type] as? FileAttributeType) == .typeDirectory else {
            return false
        }

        let appURL = resolved.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard appURL.pathExtension == "app",
              appURL.deletingLastPathComponent().path == "/Applications" else { return false }

        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let paths = ["/Applications", appURL.path, contentsURL.path, macOSURL.path, resolved.path]
        let attributes = paths.compactMap { try? FileManager.default.attributesOfItem(atPath: $0) }
        guard attributes.count == paths.count,
              (attributes[0][.ownerAccountID] as? NSNumber)?.uint32Value == 0,
              (attributes[1][.type] as? FileAttributeType) == .typeDirectory,
              (attributes[2][.type] as? FileAttributeType) == .typeDirectory,
              (attributes[3][.type] as? FileAttributeType) == .typeDirectory,
              (attributes[4][.type] as? FileAttributeType) == .typeRegular,
              let applicationsPermissions = (attributes[0][.posixPermissions] as? NSNumber)?.intValue,
              (applicationsPermissions & 0o002) == 0,
              attributes.dropFirst().allSatisfy({
                  let permissions = ($0[.posixPermissions] as? NSNumber)?.intValue ?? 0o777
                  return (permissions & 0o022) == 0
              }),
              let appOwner = (attributes[1][.ownerAccountID] as? NSNumber)?.uint32Value,
              let executableOwner = (attributes[4][.ownerAccountID] as? NSNumber)?.uint32Value,
              let appPermissions = (attributes[1][.posixPermissions] as? NSNumber)?.intValue,
              let executablePermissions = (attributes[4][.posixPermissions] as? NSNumber)?.intValue else {
            return false
        }

        return isAllowedExecutableMetadata(
            appOwnerUID: appOwner,
            executableOwnerUID: executableOwner,
            currentUID: getuid(),
            appPermissions: appPermissions,
            executablePermissions: executablePermissions
        )
    }

    /// Finder commonly installs an app in /Applications with the current user's
    /// ownership. Accept that layout when no group or other user can modify it.
    static func isAllowedExecutableMetadata(
        appOwnerUID: UInt32,
        executableOwnerUID: UInt32,
        currentUID: UInt32,
        appPermissions: Int,
        executablePermissions: Int
    ) -> Bool {
        let ownerIsTrusted = appOwnerUID == executableOwnerUID
            && (appOwnerUID == 0 || appOwnerUID == currentUID)
        return ownerIsTrusted
            && (appPermissions & 0o022) == 0
            && (executablePermissions & 0o022) == 0
    }

    private static func plistContents(
        sourceExecutablePath: String,
        ipcDirectoryPath: String,
        appVersion: String,
        helperVersion: String
    ) -> String {
        let xmlEscape: (String) -> String = { value in
            value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        }
        let escapedSourceExecutable = xmlEscape(sourceExecutablePath)
        let escapedIPC = xmlEscape(ipcDirectoryPath)
        let escapedAppVersion = xmlEscape(appVersion)
        let escapedHelperVersion = xmlEscape(helperVersion)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(helperToolPath)</string>
                <string>--smc-helper</string>
            </array>
            <key>KeepAlive</key>
            <true/>
            <key>RunAtLoad</key>
            <true/>
            <key>ProcessType</key>
            <string>Interactive</string>
            <key>EnvironmentVariables</key>
            <dict>
                <key>LLVM_PROFILE_FILE</key>
                <string>/dev/null</string>
                <key>\(SMCIPC.directoryEnvironmentKey)</key>
                <string>\(escapedIPC)</string>
                <key>\(SMCIPC.uidEnvironmentKey)</key>
                <string>\(getuid())</string>
                <key>\(sourceEnvironmentKey)</key>
                <string>\(escapedSourceExecutable)</string>
                <key>\(SMCHelperMode.helperVersionEnvironmentKey)</key>
                <string>\(escapedAppVersion)</string>
                <key>\(SMCHelperMode.helperRevisionEnvironmentKey)</key>
                <string>\(escapedHelperVersion)</string>
            </dict>
            <key>StandardOutPath</key>
            <string>\(escapedIPC)/helper-stdout.log</string>
            <key>StandardErrorPath</key>
            <string>\(escapedIPC)/helper-stderr.log</string>
        </dict>
        </plist>
        """
    }
}
