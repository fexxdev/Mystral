import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "MenuBarManager")

extension Notification.Name {
    static let menuBarSettingsChanged = Notification.Name("com.fexxdev.Mystral.menuBarSettingsChanged")
}

enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case iconOnly = "Icon Only"
    case iconAndTemperature = "Icon + Temperature"
    case iconAndRPM = "Icon + RPM"
    case iconAndProfile = "Icon + Profile"
    case temperatureOnly = "Temperature Only"
    case rpmOnly = "RPM Only"
    case miniGraph = "Mini Graph"
    case iconAndPower = "Icon + Power"
    case powerOnly = "Power Only"

    var showsIcon: Bool {
        switch self {
        case .iconOnly, .iconAndTemperature, .iconAndRPM, .iconAndProfile, .iconAndPower: return true
        case .temperatureOnly, .rpmOnly, .miniGraph, .powerOnly: return false
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

    private var liveCpuItem: NSMenuItem?
    private var liveGpuItem: NSMenuItem?
    private var liveFanItems: [NSMenuItem] = []
    private var liveProfileItems: [NSMenuItem] = []

    private let powerMonitor = PowerMonitor()

    private static let displayModeKey = "menuBarDisplayMode"
    private static let tempSourceKey = "menuBarTempSource"

    private(set) var displayMode: MenuBarDisplayMode = .iconOnly
    private(set) var tempSource: MenuBarTempSource = .cpuAverage

    init(fanController: FanController, profileManager: ProfileManager, onOpenWindow: @escaping () -> Void) {
        self.fanController = fanController
        self.profileManager = profileManager
        self.onOpenWindow = onOpenWindow
        logger.info("MenuBarManager init")
        syncFromDefaults()
        setupStatusItem()
        startUpdating()
        NotificationCenter.default.addObserver(forName: .menuBarSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                logger.info("Received .menuBarSettingsChanged notification, self is \(self == nil ? "nil" : "alive", privacy: .public)")
                self?.syncFromDefaults()
                self?.updateStatusItem()
            }
        }
    }

    func setDisplayMode(_ mode: MenuBarDisplayMode) {
        logger.info("setDisplayMode called: \(mode.rawValue, privacy: .public) (was \(self.displayMode.rawValue, privacy: .public))")
        UserDefaults.standard.set(mode.rawValue, forKey: Self.displayModeKey)
        displayMode = mode
        updateStatusItem()
    }

    func setTempSource(_ source: MenuBarTempSource) {
        logger.info("setTempSource called: \(source.rawValue, privacy: .public) (was \(self.tempSource.rawValue, privacy: .public))")
        UserDefaults.standard.set(source.rawValue, forKey: Self.tempSourceKey)
        tempSource = source
        updateStatusItem()
    }

    private func syncFromDefaults() {
        let savedMode = UserDefaults.standard.string(forKey: Self.displayModeKey)
        let savedSource = UserDefaults.standard.string(forKey: Self.tempSourceKey)
        logger.debug("syncFromDefaults — UD displayMode=\(savedMode ?? "nil", privacy: .public), UD tempSource=\(savedSource ?? "nil", privacy: .public), current displayMode=\(self.displayMode.rawValue, privacy: .public)")
        if let saved = savedMode, let mode = MenuBarDisplayMode(rawValue: saved) {
            displayMode = mode
        }
        if let saved = savedSource, let src = MenuBarTempSource(rawValue: saved) {
            tempSource = src
        }
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
        logger.info("statusItemClicked — showing context menu")
        showContextMenu()
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let sensors = fanController.sensors
        let cpuCores = SensorRegistry.cpuCoreSensors(from: sensors)
        let gpuCores = SensorRegistry.gpuCoreSensors(from: sensors)

        if !cpuCores.isEmpty {
            let item = Self.infoItem("")
            liveCpuItem = item
            menu.addItem(item)
        }
        if !gpuCores.isEmpty {
            let item = Self.infoItem("")
            liveGpuItem = item
            menu.addItem(item)
        }
        liveFanItems = []
        for _ in fanController.fans {
            let item = Self.infoItem("")
            liveFanItems.append(item)
            menu.addItem(item)
        }

        updateContextMenuItems()

        if menu.numberOfItems > 0 { menu.addItem(.separator()) }

        liveProfileItems = []
        for profile in profileManager.allProfiles {
            let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            if profile.id == profileManager.activeProfileId { item.state = .on }
            liveProfileItems.append(item)
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Mystral", action: #selector(openApp), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil

        liveCpuItem = nil
        liveGpuItem = nil
        liveFanItems = []
        liveProfileItems = []
    }

    private func updateContextMenuItems() {
        let sensors = fanController.sensors
        let cpuCores = SensorRegistry.cpuCoreSensors(from: sensors)
        let gpuCores = SensorRegistry.gpuCoreSensors(from: sensors)

        if let item = liveCpuItem, !cpuCores.isEmpty {
            let avg = cpuCores.map(\.temperature).reduce(0, +) / Double(cpuCores.count)
            let mx = cpuCores.map(\.temperature).max() ?? 0
            item.title = "CPU  \(Int(avg.rounded()))° avg  ·  \(Int(mx.rounded()))° max"
        }
        if let item = liveGpuItem, !gpuCores.isEmpty {
            let avg = gpuCores.map(\.temperature).reduce(0, +) / Double(gpuCores.count)
            let mx = gpuCores.map(\.temperature).max() ?? 0
            item.title = "GPU  \(Int(avg.rounded()))° avg  ·  \(Int(mx.rounded()))° max"
        }
        let fans = fanController.fans
        for (i, item) in liveFanItems.enumerated() where i < fans.count {
            item.title = "\(fans[i].name)  \(fans[i].currentRPM) RPM  (\(Int(fans[i].percentage))%)"
        }
        for item in liveProfileItems {
            guard let id = item.representedObject as? UUID else { continue }
            item.state = id == profileManager.activeProfileId ? .on : .off
        }
    }

    private static func infoItem(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    nonisolated static func formatTotalWatts(_ watts: Double?) -> String {
        guard let w = watts, w > 0 else { return "-- W" }
        return "\(Int(w.rounded())) W"
    }

    nonisolated static func formatPowerBreakdown(cpu: Double?, gpu: Double?) -> String? {
        var parts: [String] = []
        if let c = cpu, c >= 0 { parts.append("CPU \(Int(c.rounded())) W") }
        if let g = gpu, g >= 0 { parts.append("GPU \(Int(g.rounded())) W") }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        profileManager.activeProfileId = id
    }

    @objc private func openApp() { onOpenWindow() }

    @objc private func quitApp() { NSApp.terminate(nil) }

    private func startUpdating() {
        let timer = Timer(timeInterval: fanController.pollingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.powerMonitor.sample()
                self?.syncFromDefaults()
                self?.updateStatusItem()
                self?.updateContextMenuItems()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else {
            logger.warning("updateStatusItem — statusItem button is nil!")
            return
        }

        logger.debug("updateStatusItem — mode=\(self.displayMode.rawValue, privacy: .public)")

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
        case .iconAndPower, .powerOnly:
            button.title = prefix + powerString()
        case .miniGraph:
            break
        }
        logger.debug("updateStatusItem — title='\(button.title, privacy: .public)', hasImage=\(button.image != nil, privacy: .public)")
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

    private func powerString() -> String {
        Self.formatTotalWatts(powerMonitor.totalWatts)
    }

    private func currentTemperature() -> Double {
        let sensors = fanController.sensors
        let cpuCores = SensorRegistry.cpuCoreSensors(from: sensors)
        let gpuCores = SensorRegistry.gpuCoreSensors(from: sensors)
        switch tempSource {
        case .cpuAverage:
            if !cpuCores.isEmpty {
                return cpuCores.map(\.temperature).reduce(0, +) / Double(cpuCores.count)
            }
            return sensors.first(where: { $0.id == SensorRegistry.defaultCpuSensorKey })?.temperature ?? 0
        case .cpuMax:
            if !cpuCores.isEmpty { return cpuCores.map(\.temperature).max() ?? 0 }
            return sensors.first(where: { $0.id == SensorRegistry.defaultCpuSensorKey })?.temperature ?? 0
        case .gpuAverage:
            guard !gpuCores.isEmpty else { return 0 }
            return gpuCores.map(\.temperature).reduce(0, +) / Double(gpuCores.count)
        case .gpuMax:
            return gpuCores.map(\.temperature).max() ?? 0
        case .hottest:
            return sensors.map(\.temperature).max() ?? 0
        }
    }

    private func renderMiniGraphImage() -> NSImage {
        let cpuSensors = SensorRegistry.cpuCoreSensors(from: fanController.sensors)
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
