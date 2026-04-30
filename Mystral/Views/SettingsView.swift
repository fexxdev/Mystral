import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let fanController: FanController
    let profileManager: ProfileManager
    @State private var launchAtLogin = false
    @State private var displayMode: MenuBarDisplayMode = .iconOnly
    @State private var tempSource: MenuBarTempSource = .cpuAverage
    @State private var pollingInterval: Double = 2.0
    @State private var exportMessage: String?
    @State private var autoSwitchEnabled = true
    @State private var smoothingEnabled = true
    @State private var smoothingAlpha: Double = 0.3
    @State private var deadbandPercent: Double = 3.0
    @State private var minimumFanPct: Double = 0
    @State private var aggressiveOverride: Bool = true
    @State private var alertsEnabled = true
    @State private var alertsHighTemp: Double = 95
    @State private var alertsFanStuck = true
    @State private var stressTester = StressTester()
    @State private var updatesAutoCheck: Bool = true
    @State private var updatesStatusText: String = "Not checked yet"
    @State private var updateAvailable: Bool = false
    @State private var updateAvailableVersion: String = ""
    @State private var updateReleaseURL: URL?

    private var chipDetection: SensorRegistry.ChipDetection {
        SensorRegistry.detectChip(sensors: fanController.sensors, fans: fanController.fans)
    }

    var body: some View {
        Form {
            Section("Chip Detection") {
                LabeledContent("Detected Chip", value: chipDetection.chipName)
                LabeledContent("CPU Cores") {
                    Text("\(chipDetection.cpuCoreCount) sensors")
                }
                LabeledContent("GPU Cores") {
                    Text("\(chipDetection.gpuCoreCount) sensors")
                }
                LabeledContent("Status") {
                    HStack(spacing: 4) {
                        Image(systemName: chipDetection.isSupported ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(chipDetection.isSupported ? Color.green : Color.orange)
                        Text(chipDetection.isSupported ? "Supported" : "Partially supported — some sensors may be unmapped")
                            .foregroundStyle(chipDetection.isSupported ? Color.primary : Color.orange)
                    }
                }
                LabeledContent("Fan Control") {
                    HStack(spacing: 4) {
                        Image(systemName: chipDetection.hasFanControl ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(chipDetection.hasFanControl ? .green : .red)
                        Text(chipDetection.hasFanControl ? "Working" : "Not available (Apple Silicon limitation)")
                            .foregroundStyle(chipDetection.hasFanControl ? .primary : .secondary)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
            }
            Section("Menu Bar") {
                Picker("Display Mode", selection: $displayMode) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.onChange(of: displayMode) { _, newValue in
                    if let ad = NSApp.delegate as? AppDelegate { ad.menuBarManager?.displayMode = newValue }
                    UserDefaults.standard.set(newValue.rawValue, forKey: "menuBarDisplayMode")
                }
                if displayMode == .iconAndTemperature || displayMode == .temperatureOnly {
                    Picker("Temperature Source", selection: $tempSource) {
                        ForEach(MenuBarTempSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.onChange(of: tempSource) { _, newValue in
                        if let ad = NSApp.delegate as? AppDelegate { ad.menuBarManager?.tempSource = newValue }
                        UserDefaults.standard.set(newValue.rawValue, forKey: "menuBarTempSource")
                    }
                }
            }
            Section("Monitoring") {
                Picker("Polling Interval", selection: $pollingInterval) {
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                }.onChange(of: pollingInterval) { _, newValue in
                    fanController.pollingInterval = newValue
                    UserDefaults.standard.set(newValue, forKey: "pollingInterval")
                }
            }

            Section("Curve Behavior") {
                Toggle("Smoothing (EMA)", isOn: $smoothingEnabled)
                    .onChange(of: smoothingEnabled) { _, v in
                        fanController.smoothingEnabled = v
                        UserDefaults.standard.set(v, forKey: "smoothingEnabled")
                    }
                if smoothingEnabled {
                    HStack {
                        Text("Responsiveness")
                        Slider(value: $smoothingAlpha, in: 0.05...1.0, step: 0.05)
                            .onChange(of: smoothingAlpha) { _, v in
                                fanController.smoothingAlpha = v
                                UserDefaults.standard.set(v, forKey: "smoothingAlpha")
                            }
                        Text(String(format: "%.2f", smoothingAlpha))
                            .font(.caption.monospacedDigit()).frame(width: 40)
                    }
                }
                HStack {
                    Text("Deadband")
                    Slider(value: $deadbandPercent, in: 0...10, step: 0.5)
                        .onChange(of: deadbandPercent) { _, v in
                            fanController.deadbandPercent = v
                            UserDefaults.standard.set(v, forKey: "deadbandPercent")
                        }
                    Text("\(deadbandPercent, specifier: "%.1f")%")
                        .font(.caption.monospacedDigit()).frame(width: 50)
                }
                HStack {
                    Text("Minimum fan speed")
                    Slider(value: $minimumFanPct, in: 0...100, step: 5)
                        .onChange(of: minimumFanPct) { _, v in
                            fanController.minimumFanPercentage = v
                            UserDefaults.standard.set(v, forKey: "minimumFanPercentage")
                        }
                    Text("\(Int(minimumFanPct))%")
                        .font(.caption.monospacedDigit()).frame(width: 50)
                }
                Text("Floor that fans never go below — useful for keeping fans always spinning in summer.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Aggressively re-assert manual control", isOn: $aggressiveOverride)
                    .onChange(of: aggressiveOverride) { _, v in
                        fanController.aggressiveOverrideEnabled = v
                        UserDefaults.standard.set(v, forKey: "aggressiveOverrideEnabled")
                    }
                Text("Re-asserts forced fan mode and re-writes target speed every tick. Helps fight SMC firmware reverting your settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if HardwareInfo.isFirmwareLocked {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Limited fan control on this Mac")
                                .font(.subheadline.weight(.semibold))
                            Text("Apple firmware-locks manual fan control on M3/M4 Pro/Max MacBook Pros running macOS Sequoia and later. No third-party app — including Mystral, Macs Fan Control, or iStat — can override this. Mystral will still display sensors and fan RPM, and may partially work for some keys, but cannot reliably force fan speeds.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Link("More info", destination: URL(string: "https://github.com/crystalidea/macs-fan-control/issues/785")!)
                                .font(.caption)
                        }
                    }
                }
            }

            Section("Alerts") {
                Toggle("Enable notifications", isOn: $alertsEnabled)
                    .onChange(of: alertsEnabled) { _, v in
                        if let ad = NSApp.delegate as? AppDelegate { ad.alertManager?.enabled = v }
                    }
                if alertsEnabled {
                    HStack {
                        Text("High-temp threshold")
                        Slider(value: $alertsHighTemp, in: 70...110, step: 1)
                            .onChange(of: alertsHighTemp) { _, v in
                                if let ad = NSApp.delegate as? AppDelegate { ad.alertManager?.highTempThreshold = v }
                            }
                        Text("\(Int(alertsHighTemp))°C").font(.caption.monospacedDigit()).frame(width: 50)
                    }
                    Toggle("Alert when a fan stops responding", isOn: $alertsFanStuck)
                        .onChange(of: alertsFanStuck) { _, v in
                            if let ad = NSApp.delegate as? AppDelegate { ad.alertManager?.fanStuckEnabled = v }
                        }
                }
            }

            Section("Auto-Switch") {
                Toggle("Auto-activate profiles based on triggers", isOn: $autoSwitchEnabled)
                    .onChange(of: autoSwitchEnabled) { _, v in
                        if let ad = NSApp.delegate as? AppDelegate {
                            ad.autoSwitcher?.enabled = v
                        }
                    }
                Text("When on, profiles with triggers (power, thermal state, frontmost app) will auto-activate.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                Button("Export SMC Data for Developer") {
                    exportSMCData()
                }
                if let msg = exportMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
                stressTestRow
            }

            Section("Data") {
                Button("Reset All Settings") { resetSettings() }.foregroundStyle(.red)
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updatesAutoCheck)
                    .onChange(of: updatesAutoCheck) { _, v in
                        if let ad = NSApp.delegate as? AppDelegate { ad.updateChecker?.autoCheckEnabled = v }
                    }
                HStack {
                    Text(updatesStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if updateAvailable, updateReleaseURL != nil {
                        Button("Download Update") { openUpdateRelease() }
                    }
                    Button("Check Now") { runUpdateCheck() }
                }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                Link("GitHub", destination: URL(string: "https://github.com/fexxdev/Mystral")!)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { loadSettings() }
    }

    @ViewBuilder
    private var stressTestRow: some View {
        switch stressTester.state {
        case .idle:
            HStack {
                Button("Run 30s Stress Test") {
                    stressTester.runStressTest(durationSeconds: 30, fanController: fanController)
                }
                Text("Burns CPU on all cores and verifies fans respond.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .running(let elapsed, let total):
            HStack(spacing: 12) {
                ProgressView(value: Double(elapsed), total: Double(total))
                Text("\(elapsed) / \(total)s").font(.caption.monospacedDigit())
                Button("Stop") { stressTester.cancel() }
            }
        case .finished(let r):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: r.fanResponded ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(r.fanResponded ? Color.green : Color.orange)
                    Text(r.fanResponded ? "Fans responded" : "No clear fan response")
                        .font(.subheadline)
                }
                Text(String(format: "Temp %.0f°C → %.0f°C   |   Fan %d → %d RPM",
                            r.baselineMaxTemp, r.peakTemp, r.baselineMaxRPM, r.peakRPM))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("Run Again") {
                    stressTester.runStressTest(durationSeconds: 30, fanController: fanController)
                }
            }
        }
    }

    private func exportSMCData() {
        let content = SensorRegistry.exportDiagnosticData(sensors: fanController.sensors, fans: fanController.fans)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mystral-smc-export.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                exportMessage = "Exported to \(url.lastPathComponent)"
            } catch {
                exportMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func loadSettings() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if let s = UserDefaults.standard.string(forKey: "menuBarDisplayMode"),
           let m = MenuBarDisplayMode(rawValue: s) { displayMode = m }
        if let s = UserDefaults.standard.string(forKey: "menuBarTempSource"),
           let t = MenuBarTempSource(rawValue: s) { tempSource = t }
        let i = UserDefaults.standard.double(forKey: "pollingInterval")
        if i > 0 { pollingInterval = i }
        smoothingEnabled = fanController.smoothingEnabled
        smoothingAlpha = fanController.smoothingAlpha
        deadbandPercent = fanController.deadbandPercent
        minimumFanPct = fanController.minimumFanPercentage
        aggressiveOverride = fanController.aggressiveOverrideEnabled
        if let ad = NSApp.delegate as? AppDelegate {
            autoSwitchEnabled = ad.autoSwitcher?.enabled ?? true
            alertsEnabled = ad.alertManager?.enabled ?? true
            alertsHighTemp = ad.alertManager?.highTempThreshold ?? 95
            alertsFanStuck = ad.alertManager?.fanStuckEnabled ?? true
            updatesAutoCheck = ad.updateChecker?.autoCheckEnabled ?? true
            refreshUpdateStatus()
        }
    }

    private func refreshUpdateStatus() {
        guard let checker = (NSApp.delegate as? AppDelegate)?.updateChecker else { return }
        switch checker.status {
        case .unknown:
            if let last = checker.lastCheckedAt {
                updatesStatusText = "Last checked \(Self.relativeDateFormatter.localizedString(for: last, relativeTo: Date()))"
            } else {
                updatesStatusText = "Not checked yet"
            }
            updateAvailable = false
            updateReleaseURL = nil
        case .checking:
            updatesStatusText = "Checking for updates…"
            updateAvailable = false
        case .upToDate:
            updatesStatusText = "Up to date (v\(checker.currentVersion))"
            updateAvailable = false
            updateReleaseURL = nil
        case .updateAvailable(let version, let url, _, _):
            updatesStatusText = "Update available: v\(version) (you have v\(checker.currentVersion))"
            updateAvailable = true
            updateAvailableVersion = version
            updateReleaseURL = url
        case .error(let msg):
            updatesStatusText = "Check failed: \(msg)"
            updateAvailable = false
        }
    }

    private func runUpdateCheck() {
        guard let checker = (NSApp.delegate as? AppDelegate)?.updateChecker else { return }
        Task {
            await checker.checkForUpdates(silent: false)
            refreshUpdateStatus()
        }
        refreshUpdateStatus()
    }

    private func openUpdateRelease() {
        (NSApp.delegate as? AppDelegate)?.updateChecker?.openReleasePage()
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { launchAtLogin = !enabled }
    }

    private func resetSettings() {
        setLaunchAtLogin(false); launchAtLogin = false
        displayMode = .iconOnly; pollingInterval = 2.0
        fanController.pollingInterval = 2.0; fanController.clearAllManualOverrides()
        UserDefaults.standard.removeObject(forKey: "menuBarDisplayMode")
        UserDefaults.standard.removeObject(forKey: "menuBarTempSource")
        UserDefaults.standard.removeObject(forKey: "pollingInterval")
    }
}
