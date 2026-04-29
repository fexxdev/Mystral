import AppKit
import SwiftUI

enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconOnly = "Icon Only"
    case iconAndTemperature = "Icon + Temperature"
    case iconAndRPM = "Icon + RPM"
    case iconAndProfile = "Icon + Profile"
}

@Observable
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private let fanController: FanController
    private let profileManager: ProfileManager
    private let onOpenWindow: () -> Void
    private var updateTimer: Timer?

    var displayMode: MenuBarDisplayMode = .iconOnly {
        didSet { updateStatusItem() }
    }

    init(fanController: FanController, profileManager: ProfileManager, onOpenWindow: @escaping () -> Void) {
        self.fanController = fanController
        self.profileManager = profileManager
        self.onOpenWindow = onOpenWindow
        setupStatusItem()
        startUpdating()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "fan", accessibilityDescription: "Mystral")
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItem()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            onOpenWindow()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        for profile in profileManager.allProfiles {
            let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            if profile.id == profileManager.activeProfileId { item.state = .on }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Mystral", action: #selector(openApp), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        profileManager.activeProfileId = id
    }

    @objc private func openApp() { onOpenWindow() }

    @objc private func quitApp() { NSApp.terminate(nil) }

    private func startUpdating() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStatusItem()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        var title = ""
        switch displayMode {
        case .iconOnly: break
        case .iconAndTemperature:
            let cpuSensors = fanController.sensors.filter { $0.id.hasPrefix("Tp") }
            if !cpuSensors.isEmpty {
                let avg = cpuSensors.map(\.temperature).reduce(0, +) / Double(cpuSensors.count)
                title = " \(Int(avg))\u{00B0}"
            }
        case .iconAndRPM:
            if let fan = fanController.fans.first { title = " \(fan.currentRPM)" }
        case .iconAndProfile:
            if let profile = profileManager.activeProfile { title = " \(profile.name)" }
        }
        button.title = title
    }
}
