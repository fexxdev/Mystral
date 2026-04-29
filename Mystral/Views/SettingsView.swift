import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let fanController: FanController
    let profileManager: ProfileManager
    @State private var launchAtLogin = false
    @State private var displayMode: MenuBarDisplayMode = .iconOnly
    @State private var pollingInterval: Double = 2.0

    var body: some View {
        Form {
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
