import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let fanController: FanController
    let profileManager: ProfileManager

    @State private var launchAtLogin = false
    @State private var displayMode: MenuBarDisplayMode = .iconOnly
    @State private var tempSource: MenuBarTempSource = .cpuAverage
    @State private var pollingInterval: Double = 2.0

    @State private var smoothingEnabled = true
    @State private var smoothingAlpha: Double = 0.3
    @State private var deadbandPercent: Double = 3.0
    @State private var minimumFanPct: Double = 0
    @State private var aggressiveOverride: Bool = true

    @State private var alertsEnabled = true
    @State private var alertsHighTemp: Double = 95
    @State private var alertsFanStuck = true

    @State private var autoSwitchEnabled = true

    @State private var updatesAutoCheck: Bool = true
    @State private var updatesStatusText: String = "Not checked yet"
    @State private var updateAvailable: Bool = false
    @State private var updateAvailableVersion: String = ""
    @State private var updateReleaseURL: URL?

    @State private var stressTester = StressTester()
    @State private var exportMessage: String?

    private var chipDetection: SensorRegistry.ChipDetection {
        SensorRegistry.detectChip(sensors: fanController.sensors, fans: fanController.fans)
    }

    var body: some View {
        Form {
            chipSection
            if HardwareInfo.isFirmwareLocked { firmwareLockSection }
            generalSection
            menuBarSection
            monitoringSection
            curveSection
            alertsSection
            autoSwitchSection
            updatesSection
            diagnosticsSection
            aboutSection
            dataSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { loadSettings() }
    }

    private var chipSection: some View {
        Section("Chip Detection") {
            LabeledContent("Detected chip", value: chipDetection.chipName)
            LabeledContent("CPU cores", value: "\(chipDetection.cpuCoreCount)")
            LabeledContent("GPU cores", value: "\(chipDetection.gpuCoreCount)")
            statusRow(
                title: "Sensor coverage",
                ok: chipDetection.isSupported,
                okText: "Supported",
                badText: "Partially supported",
                badColor: .orange
            )
            statusRow(
                title: "Fan control",
                ok: chipDetection.hasFanControl,
                okText: "Working",
                badText: "Not available",
                badColor: .red
            )
        }
    }

    private var firmwareLockSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Limited fan control on this Mac")
                        .font(.subheadline.weight(.semibold))
                    Text("Apple firmware-locks manual fan control on M3/M4 Pro/Max MacBook Pros running macOS Sequoia and later. No third-party app — including Mystral, Macs Fan Control, or iStat — can override this.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Read more", destination: URL(string: "https://github.com/crystalidea/macs-fan-control/issues/785")!)
                        .font(.caption)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
        }
    }

    private var menuBarSection: some View {
        Section("Menu Bar") {
            Picker("Display mode", selection: $displayMode) {
                ForEach(MenuBarDisplayMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .onChange(of: displayMode) { _, newValue in
                if let ad = NSApp.delegate as? AppDelegate { ad.menuBarManager?.displayMode = newValue }
                UserDefaults.standard.set(newValue.rawValue, forKey: "menuBarDisplayMode")
            }
            if displayMode == .iconAndTemperature || displayMode == .temperatureOnly {
                Picker("Temperature source", selection: $tempSource) {
                    ForEach(MenuBarTempSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: tempSource) { _, newValue in
                    if let ad = NSApp.delegate as? AppDelegate { ad.menuBarManager?.tempSource = newValue }
                    UserDefaults.standard.set(newValue.rawValue, forKey: "menuBarTempSource")
                }
            }
        }
    }

    private var monitoringSection: some View {
        Section("Monitoring") {
            Picker("Polling interval", selection: $pollingInterval) {
                Text("2 seconds").tag(2.0)
                Text("5 seconds").tag(5.0)
                Text("10 seconds").tag(10.0)
            }
            .onChange(of: pollingInterval) { _, newValue in
                fanController.pollingInterval = newValue
                UserDefaults.standard.set(newValue, forKey: "pollingInterval")
            }
        }
    }

    private var curveSection: some View {
        Section("Fan Behavior") {
            Toggle("Smooth temperature changes (EMA)", isOn: $smoothingEnabled)
                .onChange(of: smoothingEnabled) { _, v in
                    fanController.smoothingEnabled = v
                    UserDefaults.standard.set(v, forKey: "smoothingEnabled")
                }
            if smoothingEnabled {
                sliderRow(title: "Responsiveness", value: $smoothingAlpha, in: 0.05...1.0, step: 0.05, valueText: smoothingAlpha.formatted(.number.precision(.fractionLength(2))))
                    .onChange(of: smoothingAlpha) { _, v in
                        fanController.smoothingAlpha = v
                        UserDefaults.standard.set(v, forKey: "smoothingAlpha")
                    }
            }
            sliderRow(title: "Deadband", value: $deadbandPercent, in: 0...10, step: 0.5, valueText: deadbandPercent.formatted(.number.precision(.fractionLength(1))) + "%")
                .onChange(of: deadbandPercent) { _, v in
                    fanController.deadbandPercent = v
                    UserDefaults.standard.set(v, forKey: "deadbandPercent")
                }
            captionText("Skip fan writes smaller than this — reduces audible RPM hunting.")

            sliderRow(title: "Minimum fan speed", value: $minimumFanPct, in: 0...100, step: 5, valueText: "\(Int(minimumFanPct))%")
                .onChange(of: minimumFanPct) { _, v in
                    fanController.minimumFanPercentage = v
                    UserDefaults.standard.set(v, forKey: "minimumFanPercentage")
                }
            captionText("Floor that fans never go below. Useful for keeping fans always spinning in summer.")

            Toggle("Aggressively re-assert manual control", isOn: $aggressiveOverride)
                .onChange(of: aggressiveOverride) { _, v in
                    fanController.aggressiveOverrideEnabled = v
                    UserDefaults.standard.set(v, forKey: "aggressiveOverrideEnabled")
                }
            captionText("Re-asserts forced fan mode every tick to fight SMC firmware reverting your settings.")
        }
    }

    private var alertsSection: some View {
        Section("Alerts") {
            Toggle("Enable notifications", isOn: $alertsEnabled)
                .onChange(of: alertsEnabled) { _, v in
                    if let ad = NSApp.delegate as? AppDelegate { ad.alertManager?.enabled = v }
                }
            if alertsEnabled {
                sliderRow(title: "High-temp threshold", value: $alertsHighTemp, in: 70...110, step: 1, valueText: "\(Int(alertsHighTemp)) °C")
                    .onChange(of: alertsHighTemp) { _, v in
                        if let ad = NSApp.delegate as? AppDelegate { ad.alertManager?.highTempThreshold = v }
                    }
                Toggle("Alert when a fan stops responding", isOn: $alertsFanStuck)
                    .onChange(of: alertsFanStuck) { _, v in
                        if let ad = NSApp.delegate as? AppDelegate { ad.alertManager?.fanStuckEnabled = v }
                    }
            }
        }
    }

    private var autoSwitchSection: some View {
        Section("Auto-Switch") {
            Toggle("Auto-activate profiles based on triggers", isOn: $autoSwitchEnabled)
                .onChange(of: autoSwitchEnabled) { _, v in
                    if let ad = NSApp.delegate as? AppDelegate { ad.autoSwitcher?.enabled = v }
                }
            captionText("Profiles with triggers (power source, thermal state, frontmost app) will auto-activate.")
        }
    }

    private var updatesSection: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $updatesAutoCheck)
                .onChange(of: updatesAutoCheck) { _, v in
                    if let ad = NSApp.delegate as? AppDelegate { ad.updateChecker?.autoCheckEnabled = v }
                }
            HStack(spacing: 8) {
                Text(updatesStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if updateAvailable, updateReleaseURL != nil {
                    Button("Download Update") { openUpdateRelease() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Button("Check Now") { runUpdateCheck() }
                    .controlSize(.small)
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            stressTestRow
            Button("Export SMC Data for Developer") { exportSMCData() }
            if let msg = exportMessage {
                captionText(msg)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
            Link("GitHub repository", destination: URL(string: "https://github.com/fexxdev/Mystral")!)
        }
    }

    private var dataSection: some View {
        Section("Data") {
            Button("Reset All Settings", role: .destructive) { resetSettings() }
        }
    }

    @ViewBuilder
    private var stressTestRow: some View {
        switch stressTester.state {
        case .idle:
            VStack(alignment: .leading, spacing: 4) {
                Button("Run 30s stress test") {
                    stressTester.runStressTest(durationSeconds: 30, fanController: fanController)
                }
                captionText("Burns CPU on all cores and verifies fans respond.")
            }
        case .running(let elapsed, let total):
            HStack(spacing: 12) {
                ProgressView(value: Double(elapsed), total: Double(total))
                Text("\(elapsed) / \(total) s").font(.caption.monospacedDigit()).frame(width: 64, alignment: .trailing)
                Button("Stop") { stressTester.cancel() }.controlSize(.small)
            }
        case .finished(let r):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: r.fanResponded ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(r.fanResponded ? Color.green : Color.orange)
                    Text(r.fanResponded ? "Fans responded" : "No clear fan response")
                        .font(.subheadline.weight(.medium))
                }
                Text("Temp \(Int(r.baselineMaxTemp))°C → \(Int(r.peakTemp))°C   |   Fan \(r.baselineMaxRPM) → \(r.peakRPM) RPM")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Run again") {
                    stressTester.runStressTest(durationSeconds: 30, fanController: fanController)
                }.controlSize(.small)
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, valueText: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(minWidth: 160, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }

    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusRow(title: String, ok: Bool, okText: String, badText: String, badColor: Color) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? Color.green : badColor)
                Text(ok ? okText : badText)
                    .foregroundStyle(ok ? .primary : badColor)
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
        displayMode = .iconOnly
        if let ad = NSApp.delegate as? AppDelegate { ad.menuBarManager?.displayMode = .iconOnly }
        pollingInterval = 2.0
        fanController.pollingInterval = 2.0
        fanController.clearAllManualOverrides()
        fanController.minimumFanPercentage = 0
        minimumFanPct = 0
        UserDefaults.standard.removeObject(forKey: "menuBarDisplayMode")
        UserDefaults.standard.removeObject(forKey: "menuBarTempSource")
        UserDefaults.standard.removeObject(forKey: "pollingInterval")
        UserDefaults.standard.removeObject(forKey: "minimumFanPercentage")
    }
}
