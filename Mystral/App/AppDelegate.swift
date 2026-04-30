import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    var menuBarManager: MenuBarManager?
    var fanController: FanController?
    var profileManager: ProfileManager?
    private var smcProxy: SMCProxyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        profileManager = ProfileManager()

        let smcService: SMCServiceProtocol
        if getuid() == 0 {
            do {
                smcService = try SMCService()
                logger.info("Running as root — direct SMC access")
            } catch {
                logger.error("SMC init failed as root: \(error.localizedDescription)")
                smcService = FallbackSMCService()
            }
        } else {
            let proxy = SMCProxyService()
            smcProxy = proxy
            smcService = proxy
            launchHelperAsync()
        }

        fanController = FanController(smcService: smcService, profileManager: profileManager!)
        menuBarManager = MenuBarManager(
            fanController: fanController!,
            profileManager: profileManager!,
            onOpenWindow: { [weak self] in self?.openMainWindow() }
        )
        fanController!.start()
    }

    private func launchHelperAsync() {
        if isHelperRunning() {
            logger.info("Helper already running")
            return
        }
        Task.detached {
            await self.launchHelper()
        }
    }

    private func launchHelper() {
        guard let execPath = Bundle.main.executablePath else { return }
        let escaped = execPath.replacingOccurrences(of: "'", with: "'\\''")
        let script = "do shell script \"'\(escaped)' --smc-helper >/tmp/mystral-helper-stdout.log 2>/tmp/mystral-helper-stderr.log &\" with administrator privileges"
        guard let appleScript = NSAppleScript(source: script) else { return }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error {
            logger.error("Helper launch failed: \(error)")
        } else {
            logger.info("Helper launched successfully")
        }
    }

    private func isHelperRunning() -> Bool {
        guard let pidStr = try? String(contentsOfFile: SMCHelperMode.pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidStr) else { return false }
        return kill(pid, 0) == 0
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        fanController?.stop()
        killHelper()
    }

    private func killHelper() {
        guard let pidStr = try? String(contentsOfFile: SMCHelperMode.pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidStr) else { return }
        kill(pid, SIGTERM)
    }

    func openMainWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let contentView = MainView(
            fanController: fanController!,
            profileManager: profileManager!
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mystral"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.setFrameAutosaveName("MystralMainWindow")
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        self.window = window
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
