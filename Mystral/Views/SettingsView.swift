import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let fanController: FanController
    let profileManager: ProfileManager
    @State private var launchAtLogin = false
    @State private var displayMode: MenuBarDisplayMode = .iconOnly
    @State private var pollingInterval: Double = 2.0
    @State private var exportMessage: String?

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

            Section("Diagnostics") {
                Button("Export SMC Data for Developer") {
                    exportSMCData()
                }
                if let msg = exportMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                Button("Reset All Settings") { resetSettings() }.foregroundStyle(.red)
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
        let i = UserDefaults.standard.double(forKey: "pollingInterval")
        if i > 0 { pollingInterval = i }
    }

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
        UserDefaults.standard.removeObject(forKey: "pollingInterval")
    }
}
