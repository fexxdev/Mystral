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
            launchHelperAsync()
        }

        fanController = FanController(smcService: smcService, profileManager: profileManager!)
        fanController!.helperRestarter = { [weak self] in
            self?.launchHelperAsync()
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

    private func launchHelperAsync() {
        let helperState = checkHelper()
        switch helperState {
        case .running:
            logger.info("Helper already running (version match)")
            return
        case .staleOrMismatch(let pid):
            logger.info("Helper version mismatch or stale — killing old helper")
            kill(pid, SIGTERM)
            usleep(500_000)
        case .notRunning:
            break
        }
        Task.detached {
            await self.launchHelper()
        }
    }

    private enum HelperState {
        case running
        case staleOrMismatch(pid: Int32)
        case notRunning
    }

    private func checkHelper() -> HelperState {
        guard let pidStr = try? String(contentsOfFile: SMCHelperMode.pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidStr),
              kill(pid, 0) == 0 else { return .notRunning }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: SMCHelperMode.dataPath)),
              let smcData = try? JSONDecoder().decode(SMCHelperMode.SMCData.self, from: data) else {
            return .staleOrMismatch(pid: pid)
        }

        if smcData.version != SMCHelperMode.appVersion {
            return .staleOrMismatch(pid: pid)
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: SMCHelperMode.dataPath)
        if let modified = attrs?[.modificationDate] as? Date, Date().timeIntervalSince(modified) < 10 {
            return .running
        }
        return .staleOrMismatch(pid: pid)
    }

    private func launchHelper() {
        guard let execPath = Bundle.main.executablePath else { return }
        let escaped = execPath.replacingOccurrences(of: "'", with: "'\\''")
        let script = "do shell script \"'\(escaped)' --smc-helper >/tmp/mystral-helper-stdout.log 2>/tmp/mystral-helper-stderr.log &\" with administrator privileges"
        guard let appleScript = NSAppleScript(source: script) else { return }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error {
            logger.error("Helper launch failed: \(error, privacy: .public)")
        } else {
            logger.info("Helper launched successfully")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("applicationWillTerminate — stopping fan controller and killing helper")
        fanController?.stop()
        killHelper()
    }

    private func killHelper() {
        guard let pidStr = try? String(contentsOfFile: SMCHelperMode.pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidStr) else { return }
        kill(pid, SIGTERM)
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
