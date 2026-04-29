import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case sensors = "Sensors"
    case fans = "Fans"
    case profiles = "Profiles"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: "gauge"
        case .sensors: "thermometer.medium"
        case .fans: "fan"
        case .profiles: "list.bullet"
        case .settings: "gear"
        }
    }

    var localizedName: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

struct MainView: View {
    let fanController: FanController
    let profileManager: ProfileManager
    @State private var selectedItem: SidebarItem = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.localizedName, systemImage: item.icon).tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Active Profile").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { profileManager.activeProfileId },
                    set: { profileManager.activeProfileId = $0 }
                )) {
                    ForEach(profileManager.allProfiles) { profile in
                        Label(profile.name, systemImage: profile.icon).tag(Optional(profile.id))
                    }
                }.labelsHidden()
            }.padding()
        } detail: {
            switch selectedItem {
            case .dashboard: DashboardView(fanController: fanController, profileManager: profileManager)
            case .sensors: SensorsView(fanController: fanController)
            case .fans: FansView(fanController: fanController)
            case .profiles: ProfilesView(fanController: fanController, profileManager: profileManager)
            case .settings: SettingsView(fanController: fanController, profileManager: profileManager)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
