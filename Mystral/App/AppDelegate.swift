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
    private var didRequestUpgradeRestart = false

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
        if HelperDaemon.isInstalled(forExecutable: execPath) {
            // Prompt-free: ask the running helper to recycle; the launchd daemon's
            // KeepAlive relaunches it immediately (also picks up a new binary).
            smcProxy?.requestRestart()
        } else {
            ensureHelperInstalled()
        }
    }

    /// Ensures the privileged SMC helper is installed as a launchd daemon. The first
    /// install triggers ONE admin prompt; afterwards launchd keeps the helper alive
    /// forever, so this is a no-op on later launches. If the app was updated in place,
    /// recycles the running helper prompt-free so launchd loads the new binary.
    private func ensureHelperInstalled() {
        guard smcProxy != nil, let execPath = Bundle.main.executablePath else { return }

        if HelperDaemon.isInstalled(forExecutable: execPath) {
            helperLaunchFailures = 0
            requestUpgradeRestartIfNeeded()
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
            let ok = HelperDaemon.install(executablePath: execPath)
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

    /// After an in-place app update the daemon (same path) still runs the old binary.
    /// If the running helper reports an older version on fresh data, ask it to recycle
    /// so launchd relaunches the new on-disk binary — no admin prompt. At most once per run.
    private func requestUpgradeRestartIfNeeded() {
        guard !didRequestUpgradeRestart,
              let data = try? Data(contentsOf: URL(fileURLWithPath: SMCHelperMode.dataPath)),
              let smcData = try? JSONDecoder().decode(SMCHelperMode.SMCData.self, from: data),
              let version = smcData.version, version != SMCHelperMode.appVersion,
              let attrs = try? FileManager.default.attributesOfItem(atPath: SMCHelperMode.dataPath),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < 30 else { return }
        logger.info("Helper version \(version, privacy: .public) != app \(SMCHelperMode.appVersion, privacy: .public) — requesting prompt-free restart")
        didRequestUpgradeRestart = true
        smcProxy?.requestRestart()
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
}

/// Installs and tracks the privileged SMC helper as a launchd LaunchDaemon.
///
/// Previously the helper was spawned as a root *orphan* via `osascript … with
/// administrator privileges` and backgrounded. launchd (pid 1) adopts such orphans
/// and reaps them during housekeeping (~every 20–40 min), forcing a fresh admin
/// prompt each time. As a managed LaunchDaemon with KeepAlive, launchd instead keeps
/// the helper alive forever and revives it in <1s on any death — one admin prompt at
/// install, never again.
enum HelperDaemon {
    static let label = "com.fexxdev.Mystral.helper"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    /// True if the daemon plist is installed AND points at `executablePath`. A path
    /// mismatch means the app was moved/reinstalled elsewhere and needs a repair install.
    static func isInstalled(forExecutable executablePath: String) -> Bool {
        guard let dict = NSDictionary(contentsOfFile: plistPath),
              let args = dict["ProgramArguments"] as? [String],
              let program = args.first else { return false }
        return program == executablePath
    }

    /// Installs/repairs the daemon. Triggers ONE admin password prompt. Returns true
    /// on success. Safe to call when already installed (re-bootstraps cleanly).
    @discardableResult
    static func install(executablePath: String) -> Bool {
        let staged = "/tmp/\(label).plist"
        guard (try? plistContents(executablePath: executablePath)
            .write(toFile: staged, atomically: true, encoding: .utf8)) != nil else {
            logger.error("Failed to stage daemon plist in /tmp")
            return false
        }

        // As root: drop any prior job + stray orphan helpers, install the plist, then
        // bootstrap/enable/kickstart so launchd starts and keeps the helper alive.
        let installScript = """
        #!/bin/bash
        LOG=/tmp/mystral-daemon-install.log
        echo "=== install $(date) uid=$(id -u) ===" >> "$LOG"
        launchctl bootout system/\(label) 2>/dev/null || true
        pkill -f -- '--smc-helper' 2>/dev/null || true
        cp '\(staged)' '\(plistPath)' && chown root:wheel '\(plistPath)' && chmod 644 '\(plistPath)' || { echo "plist install FAILED" >> "$LOG"; exit 1; }
        launchctl enable system/\(label) 2>/dev/null || true
        launchctl bootstrap system '\(plistPath)' 2>>"$LOG" || true
        launchctl kickstart system/\(label) 2>>"$LOG" || true
        echo "install OK" >> "$LOG"
        """
        try? installScript.write(toFile: "/tmp/mystral-daemon-install.sh", atomically: true, encoding: .utf8)
        chmod("/tmp/mystral-daemon-install.sh", 0o755)

        let osa = "do shell script \"bash /tmp/mystral-daemon-install.sh\" with administrator privileges"
        guard let script = NSAppleScript(source: osa) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? -1
            logger.error("Daemon install failed (code=\(code, privacy: .public)): \(error, privacy: .public)")
            return false
        }
        return isInstalled(forExecutable: executablePath)
    }

    private static func plistContents(executablePath: String) -> String {
        let escaped = executablePath
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(escaped)</string>
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
            </dict>
            <key>StandardOutPath</key>
            <string>/tmp/mystral-helper-stdout.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/mystral-helper-stderr.log</string>
        </dict>
        </plist>
        """
    }
}
