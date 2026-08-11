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
    static let sidebarWidth: CGFloat = 200

    let fanController: FanController
    let profileManager: ProfileManager
    let alertManager: AlertManager?
    let autoSwitcher: ProfileAutoSwitcher?
    let updateChecker: UpdateChecker?
    @State private var selectedItem: SidebarItem = .dashboard
    @State private var isSidebarVisible = true

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if isSidebarVisible {
                    sidebar
                    Divider()
                }

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(selectedItem.localizedName)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
                .accessibilityLabel("Toggle Sidebar")
            }
        }
        .frame(minWidth: 1200, minHeight: 640)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.localizedName, systemImage: item.icon).tag(item)
            }
            .listStyle(.sidebar)
            .frame(maxHeight: .infinity)

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
                }
                .labelsHidden()
            }
            .padding()
        }
        .frame(width: Self.sidebarWidth)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .dashboard: DashboardView(fanController: fanController, profileManager: profileManager)
        case .sensors: SensorsView(fanController: fanController)
        case .fans: FansView(fanController: fanController)
        case .profiles: ProfilesView(fanController: fanController, profileManager: profileManager)
        case .settings: SettingsView(fanController: fanController, profileManager: profileManager, alertManager: alertManager, autoSwitcher: autoSwitcher, updateChecker: updateChecker)
        }
    }
}
