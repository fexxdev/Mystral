import SwiftUI
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "SettingsView")

struct SettingsView: View {
    let fanController: FanController
    let profileManager: ProfileManager
    let alertManager: AlertManager?
    let autoSwitcher: ProfileAutoSwitcher?
    let updateChecker: UpdateChecker?

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
                logger.info("Settings: displayMode picker changed to \(newValue.rawValue, privacy: .public)")
                UserDefaults.standard.set(newValue.rawValue, forKey: "menuBarDisplayMode")
                logger.info("Settings: wrote UD, posting .menuBarSettingsChanged")
                NotificationCenter.default.post(name: .menuBarSettingsChanged, object: nil)
                logger.info("Settings: notification posted")
            }
            if displayMode == .iconAndTemperature || displayMode == .temperatureOnly {
                Picker("Temperature source", selection: $tempSource) {
                    ForEach(MenuBarTempSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: tempSource) { _, newValue in
                    logger.info("Settings: tempSource picker changed to \(newValue.rawValue, privacy: .public)")
                    UserDefaults.standard.set(newValue.rawValue, forKey: "menuBarTempSource")
                    NotificationCenter.default.post(name: .menuBarSettingsChanged, object: nil)
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
                    alertManager?.enabled = v
                }
            if alertsEnabled {
                sliderRow(title: "High-temp threshold", value: $alertsHighTemp, in: 70...110, step: 1, valueText: "\(Int(alertsHighTemp)) °C")
                    .onChange(of: alertsHighTemp) { _, v in
                        alertManager?.highTempThreshold = v
                    }
                Toggle("Alert when a fan stops responding", isOn: $alertsFanStuck)
                    .onChange(of: alertsFanStuck) { _, v in
                        alertManager?.fanStuckEnabled = v
                    }
            }
        }
    }

    private var autoSwitchSection: some View {
        Section("Auto-Switch") {
            Toggle("Auto-activate profiles based on triggers", isOn: $autoSwitchEnabled)
                .onChange(of: autoSwitchEnabled) { _, v in
                    autoSwitcher?.enabled = v
                }
            captionText("Profiles with triggers (power source, thermal state, frontmost app) will auto-activate.")
        }
    }

    private var updatesSection: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $updatesAutoCheck)
                .onChange(of: updatesAutoCheck) { _, v in
                    updateChecker?.autoCheckEnabled = v
                }
            updateStatusRow
        }
    }

    @ViewBuilder
    private var updateStatusRow: some View {
        if let checker = updateChecker {
            switch checker.status {
            case .downloading(_, let progress):
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                    HStack {
                        Text("Downloading… \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { checker.cancelInstall() }
                            .controlSize(.small)
                    }
                }
            case .installing(let version):
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing v\(version)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .updateAvailable(let version, _, let dmgURL, _):
                HStack(spacing: 8) {
                    Text("v\(version) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if dmgURL != nil {
                        Button("Install Update") {
                            Task { await checker.installUpdate() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button("View Release") { checker.openReleasePage() }
                            .controlSize(.small)
                    }
                }
            case .error(let msg):
                HStack(spacing: 8) {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                    if checker.pendingUpdate != nil {
                        Button("Retry") {
                            checker.retryInstall()
                        }
                        .controlSize(.small)
                    }
                    Button("Check Now") { runUpdateCheck() }
                        .controlSize(.small)
                }
            case .checking:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking for updates…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .upToDate:
                HStack(spacing: 8) {
                    Text("Up to date (v\(checker.currentVersion))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { runUpdateCheck() }
                        .controlSize(.small)
                }
            case .unknown:
                HStack(spacing: 8) {
                    Text(unknownStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { runUpdateCheck() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var unknownStatusText: String {
        if let last = updateChecker?.lastCheckedAt {
            return "Last checked \(Self.relativeDateFormatter.localizedString(for: last, relativeTo: Date()))"
        }
        return "Not checked yet"
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
        logger.info("loadSettings called")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if let s = UserDefaults.standard.string(forKey: "menuBarDisplayMode"),
           let m = MenuBarDisplayMode(rawValue: s) {
            logger.info("loadSettings: UD displayMode=\(s, privacy: .public)")
            displayMode = m
        }
        if let s = UserDefaults.standard.string(forKey: "menuBarTempSource"),
           let t = MenuBarTempSource(rawValue: s) { tempSource = t }
        let i = UserDefaults.standard.double(forKey: "pollingInterval")
        if i > 0 { pollingInterval = i }
        smoothingEnabled = fanController.smoothingEnabled
        smoothingAlpha = fanController.smoothingAlpha
        deadbandPercent = fanController.deadbandPercent
        minimumFanPct = fanController.minimumFanPercentage
        aggressiveOverride = fanController.aggressiveOverrideEnabled
        autoSwitchEnabled = autoSwitcher?.enabled ?? true
        alertsEnabled = alertManager?.enabled ?? true
        alertsHighTemp = alertManager?.highTempThreshold ?? 95
        alertsFanStuck = alertManager?.fanStuckEnabled ?? true
        updatesAutoCheck = updateChecker?.autoCheckEnabled ?? true
        logger.info("loadSettings: alertManager=\(self.alertManager == nil ? "nil" : "exists", privacy: .public), autoSwitcher=\(self.autoSwitcher == nil ? "nil" : "exists", privacy: .public), updateChecker=\(self.updateChecker == nil ? "nil" : "exists", privacy: .public)")
    }

    private func runUpdateCheck() {
        guard let checker = updateChecker else { return }
        Task { await checker.checkForUpdates(silent: false) }
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
        tempSource = .cpuAverage
        pollingInterval = 2.0
        smoothingEnabled = true
        smoothingAlpha = 0.3
        deadbandPercent = 3.0
        minimumFanPct = 0
        aggressiveOverride = true

        fanController.pollingInterval = 2.0
        fanController.smoothingEnabled = true
        fanController.smoothingAlpha = 0.3
        fanController.deadbandPercent = 3.0
        fanController.minimumFanPercentage = 0
        fanController.aggressiveOverrideEnabled = true
        fanController.clearAllManualOverrides()

        for key in ["menuBarDisplayMode", "menuBarTempSource", "pollingInterval",
                     "smoothingEnabled", "smoothingAlpha", "deadbandPercent",
                     "minimumFanPercentage", "aggressiveOverrideEnabled"] {
            UserDefaults.standard.removeObject(forKey: key)
        }

        NotificationCenter.default.post(name: .menuBarSettingsChanged, object: nil)
    }
}
