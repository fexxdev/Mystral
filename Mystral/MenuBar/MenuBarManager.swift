import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "MenuBarManager")

enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconOnly = "Icon Only"
    case iconAndTemperature = "Icon + Temperature"
    case iconAndRPM = "Icon + RPM"
    case iconAndProfile = "Icon + Profile"
    case temperatureOnly = "Temperature Only"
    case rpmOnly = "RPM Only"
    case miniGraph = "Mini Graph"

    var showsIcon: Bool {
        switch self {
        case .iconOnly, .iconAndTemperature, .iconAndRPM, .iconAndProfile: return true
        case .temperatureOnly, .rpmOnly, .miniGraph: return false
        }
    }
}

enum MenuBarTempSource: String, CaseIterable, Codable {
    case cpuAverage = "CPU Average"
    case cpuMax = "CPU Max"
    case gpuAverage = "GPU Average"
    case gpuMax = "GPU Max"
    case hottest = "Hottest Sensor"
}

@Observable
@MainActor
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private let fanController: FanController
    private let profileManager: ProfileManager
    private let onOpenWindow: () -> Void
    private var updateTimer: Timer?

    private static let displayModeKey = "menuBarDisplayMode"
    private static let tempSourceKey = "menuBarTempSource"

    var displayMode: MenuBarDisplayMode = .iconOnly {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeKey)
            updateStatusItem()
        }
    }

    var tempSource: MenuBarTempSource = .cpuAverage {
        didSet {
            UserDefaults.standard.set(tempSource.rawValue, forKey: Self.tempSourceKey)
            updateStatusItem()
        }
    }

    init(fanController: FanController, profileManager: ProfileManager, onOpenWindow: @escaping () -> Void) {
        self.fanController = fanController
        self.profileManager = profileManager
        self.onOpenWindow = onOpenWindow
        if let saved = UserDefaults.standard.string(forKey: Self.displayModeKey),
           let mode = MenuBarDisplayMode(rawValue: saved) {
            self.displayMode = mode
        }
        if let saved = UserDefaults.standard.string(forKey: Self.tempSourceKey),
           let src = MenuBarTempSource(rawValue: saved) {
            self.tempSource = src
        }
        setupStatusItem()
        startUpdating()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = Self.makeStatusIcon()
        button.imagePosition = .imageLeft
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItem()
    }

    private static func makeStatusIcon() -> NSImage? {
        let symbolNames = ["fanblades.fill", "fanblades", "fan.fill", "fan"]
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(.init(scale: .medium))
        for name in symbolNames {
            if let img = NSImage(systemSymbolName: name, accessibilityDescription: "Mystral")?
                .withSymbolConfiguration(config) {
                img.isTemplate = true
                return img
            }
        }
        return nil
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { onOpenWindow(); return }
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
            MainActor.assumeIsolated {
                self?.updateStatusItem()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        if displayMode == .miniGraph {
            button.image = renderMiniGraphImage()
            button.title = ""
            return
        }

        button.image = displayMode.showsIcon ? Self.makeStatusIcon() : nil

        let prefix = displayMode.showsIcon ? " " : ""
        switch displayMode {
        case .iconOnly:
            button.title = ""
        case .iconAndTemperature, .temperatureOnly:
            button.title = prefix + temperatureString()
        case .iconAndRPM, .rpmOnly:
            button.title = prefix + rpmString()
        case .iconAndProfile:
            if let profile = profileManager.activeProfile {
                button.title = prefix + profile.name
            } else {
                button.title = ""
            }
        case .miniGraph:
            break
        }
    }

    private func temperatureString() -> String {
        let value = currentTemperature()
        guard value > 0 else { return "--°" }
        return "\(Int(value.rounded()))°"
    }

    private func rpmString() -> String {
        guard let fan = fanController.fans.first else { return "-- RPM" }
        return "\(fan.currentRPM)"
    }

    private func currentTemperature() -> Double {
        let sensors = fanController.sensors
        let cpu = sensors.filter { $0.id.hasPrefix("Tp") }
        let gpu = sensors.filter { $0.id.hasPrefix("Tg") }
        switch tempSource {
        case .cpuAverage:
            guard !cpu.isEmpty else { return 0 }
            return cpu.map(\.temperature).reduce(0, +) / Double(cpu.count)
        case .cpuMax:
            return cpu.map(\.temperature).max() ?? 0
        case .gpuAverage:
            guard !gpu.isEmpty else { return 0 }
            return gpu.map(\.temperature).reduce(0, +) / Double(gpu.count)
        case .gpuMax:
            return gpu.map(\.temperature).max() ?? 0
        case .hottest:
            return sensors.map(\.temperature).max() ?? 0
        }
    }

    private func renderMiniGraphImage() -> NSImage {
        let cpuSensors = fanController.sensors.filter { $0.id.hasPrefix("Tp") }
        let history: [Double]
        if !cpuSensors.isEmpty {
            let len = cpuSensors.map { $0.history.count }.max() ?? 0
            var avgs: [Double] = []
            for i in 0..<len {
                let vals = cpuSensors.compactMap { $0.history.count > i ? $0.history[i] : nil }
                if !vals.isEmpty { avgs.append(vals.reduce(0, +) / Double(vals.count)) }
            }
            history = avgs
        } else {
            history = []
        }
        let currentTemp = history.last ?? 0
        let currentRPM = fanController.fans.first?.currentRPM ?? 0
        let stroke = Self.lineColor(for: currentTemp)

        let width: CGFloat = 78
        let height: CGFloat = 22
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let chartWidth: CGFloat = 36
            let chartX: CGFloat = 0
            let chartY: CGFloat = 2
            let chartH: CGFloat = 18

            NSColor.clear.setFill()
            rect.fill()

            if history.count > 1 {
                let path = NSBezierPath()
                let minT: Double = 30
                let maxT: Double = 100
                for (i, t) in history.suffix(36).enumerated() {
                    let suffixStart = max(0, history.count - 36)
                    let count = history.count - suffixStart
                    let x = chartX + chartWidth * CGFloat(i) / CGFloat(max(count - 1, 1))
                    let normalized = (max(minT, min(maxT, t)) - minT) / (maxT - minT)
                    let y = chartY + chartH * CGFloat(normalized)
                    if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
                }
                path.lineWidth = 1.2
                stroke.setStroke()
                path.stroke()
            }

            let tempStr = "\(Int(currentTemp))°"
            let rpmStr = "\(currentRPM)"
            let tempAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            let rpmAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            tempStr.draw(at: NSPoint(x: chartWidth + 4, y: 11), withAttributes: tempAttrs)
            rpmStr.draw(at: NSPoint(x: chartWidth + 4, y: 1), withAttributes: rpmAttrs)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func lineColor(for temp: Double) -> NSColor {
        switch temp {
        case ..<50: return .systemGreen
        case 50..<70: return .systemYellow
        case 70..<85: return .systemOrange
        default: return .systemRed
        }
    }
}
