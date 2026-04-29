import SwiftUI

struct ProfilesView: View {
    let fanController: FanController
    let profileManager: ProfileManager
    @State private var editingProfile: Profile?
    @State private var showDeleteConfirmation = false
    @State private var profileToDelete: Profile?
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        HSplitView {
            profileList.frame(minWidth: 220, maxWidth: 300)
            profileDetail.frame(maxWidth: .infinity)
        }
        .navigationTitle("Profiles")
        .alert("Delete Profile", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let p = profileToDelete {
                    try? profileManager.deleteCustomProfile(id: p.id)
                    if editingProfile?.id == p.id { editingProfile = nil }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Are you sure you want to delete \"\(profileToDelete?.name ?? "")\"?") }
    }

    private var profileList: some View {
        List {
            Section("Presets") {
                ForEach(profileManager.presets) { p in profileRow(p, isPreset: true) }
            }
            Section("Custom (\(profileManager.customProfiles.count)/\(ProfileManager.maxCustomProfiles))") {
                ForEach(profileManager.customProfiles) { p in profileRow(p, isPreset: false) }
                if profileManager.customProfiles.count < ProfileManager.maxCustomProfiles {
                    Button {
                        let newP = Profile(name: "New Profile", curvePoints: [
                            CurvePoint(temperature: 30, fanPercentage: 15),
                            CurvePoint(temperature: 60, fanPercentage: 50),
                            CurvePoint(temperature: 90, fanPercentage: 100)
                        ])
                        try? profileManager.saveCustomProfile(newP)
                        editingProfile = newP
                    } label: { Label("Add Profile", systemImage: "plus") }
                }
            }
        }
    }

    private func profileRow(_ profile: Profile, isPreset: Bool) -> some View {
        HStack {
            Image(systemName: profile.icon)
            Text(profile.name)
            Spacer()
            if profile.id == profileManager.activeProfileId {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editingProfile = profile }
        .contextMenu {
            Button("Activate") { profileManager.activeProfileId = profile.id }
            if isPreset {
                Button("Duplicate as Custom") {
                    if let copy = try? profileManager.duplicateAsCustom(profile) { editingProfile = copy }
                }
            } else {
                Button("Delete", role: .destructive) { profileToDelete = profile; showDeleteConfirmation = true }
            }
        }
    }

    private func debounceSave(_ profile: Profile) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            try? profileManager.saveCustomProfile(profile)
        }
    }

    private var profileDetail: some View {
        Group {
            if var profile = editingProfile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !profile.isPreset {
                            TextField("Profile Name", text: Binding(
                                get: { profile.name },
                                set: { profile.name = $0; editingProfile = profile; debounceSave(profile) }
                            )).textFieldStyle(.roundedBorder).font(.title2)
                        } else {
                            HStack {
                                Image(systemName: "lock")
                                Text(profile.name).font(.title2.bold())
                                Text("(Preset — read only)").foregroundStyle(.secondary)
                            }
                        }
                        CurveEditorView(
                            curvePoints: Binding(
                                get: { profile.curvePoints },
                                set: { profile.curvePoints = $0; editingProfile = profile
                                    if !profile.isPreset { debounceSave(profile) } }
                            ),
                            sensorKeys: fanController.sensors.map(\.id),
                            sensorKey: Binding(
                                get: { profile.sensorKey },
                                set: { profile.sensorKey = $0; editingProfile = profile
                                    if !profile.isPreset { try? profileManager.saveCustomProfile(profile) } }
                            )
                        ).disabled(profile.isPreset).opacity(profile.isPreset ? 0.7 : 1.0)
                    }.padding()
                }
            } else {
                ContentUnavailableView("Select a Profile", systemImage: "list.bullet",
                                       description: Text("Choose a profile from the list to view or edit its fan curve."))
            }
        }
    }
}
