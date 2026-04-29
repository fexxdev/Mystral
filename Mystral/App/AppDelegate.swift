import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    var menuBarManager: MenuBarManager?
    var fanController: FanController?
    var profileManager: ProfileManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        profileManager = ProfileManager()

        let smcService: SMCServiceProtocol
        do {
            smcService = try SMCService()
        } catch {
            smcService = FallbackSMCService()
        }

        fanController = FanController(smcService: smcService, profileManager: profileManager!)

        menuBarManager = MenuBarManager(
            fanController: fanController!,
            profileManager: profileManager!,
            onOpenWindow: { [weak self] in self?.openMainWindow() }
        )

        fanController!.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        fanController?.stop()
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
}
