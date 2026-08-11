import SwiftUI

struct ProfilesView: View {
    static let sidebarWidth: CGFloat = 260

    let fanController: FanController
    let profileManager: ProfileManager
    @State private var selectedProfileId: UUID?
    @State private var showDeleteConfirmation = false
    @State private var profileToDelete: Profile?
    @State private var saveTask: Task<Void, Never>?
    @State private var operationError: String?

    private var selectedProfile: Profile? {
        guard let id = selectedProfileId else { return nil }
        return profileManager.allProfiles.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selectedProfileId == nil {
                selectedProfileId = profileManager.activeProfileId ?? profileManager.allProfiles.first?.id
            }
        }
        .alert("Delete Profile", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let p = profileToDelete {
                    do {
                        try profileManager.deleteCustomProfile(id: p.id)
                        if selectedProfileId == p.id { selectedProfileId = profileManager.activeProfileId }
                    } catch {
                        operationError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Are you sure you want to delete \"\(profileToDelete?.name ?? "")\"?") }
        .alert("Profile Error", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK") { operationError = nil }
        } message: {
            Text(operationError ?? "Profile operation failed")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Presets")
            ForEach(profileManager.presets) { p in profileRow(p, isPreset: true) }

            sectionHeader("Custom (\(profileManager.customProfiles.count)/\(ProfileManager.maxCustomProfiles))")
            ForEach(profileManager.customProfiles) { p in profileRow(p, isPreset: false) }

            if profileManager.customProfiles.count < ProfileManager.maxCustomProfiles {
                Button {
                    let newP = Profile(name: "New Profile", curvePoints: [
                        CurvePoint(temperature: 30, fanPercentage: 15),
                        CurvePoint(temperature: 60, fanPercentage: 50),
                        CurvePoint(temperature: 90, fanPercentage: 100)
                    ])
                    do {
                        try profileManager.saveCustomProfile(newP)
                        selectedProfileId = newP.id
                    } catch {
                        operationError = error.localizedDescription
                    }
                } label: {
                    Label("New Profile", systemImage: "plus")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func profileRow(_ profile: Profile, isPreset: Bool) -> some View {
        let isSelected = profile.id == selectedProfileId
        let isActive = profile.id == profileManager.activeProfileId

        return HStack(spacing: 10) {
            Image(systemName: profile.icon)
                .frame(width: 20)
                .foregroundStyle(isSelected ? Color.white : .primary)
            Text(profile.name)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : .primary)
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white : Color.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { selectedProfileId = profile.id }
        .contextMenu {
            if !isActive {
                Button("Activate") { profileManager.activeProfileId = profile.id }
            }
            if isPreset {
                Button("Duplicate as Custom") {
                    do {
                        let copy = try profileManager.duplicateAsCustom(profile)
                        selectedProfileId = copy.id
                    } catch {
                        operationError = error.localizedDescription
                    }
                }
            } else {
                Button("Delete", role: .destructive) {
                    profileToDelete = profile
                    showDeleteConfirmation = true
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let profile = selectedProfile {
            profileDetailContent(profile)
        } else {
            ContentUnavailableView("Select a Profile", systemImage: "list.bullet",
                                   description: Text("Choose a profile from the list to view or edit its fan curve."))
        }
    }

    private func profileDetailContent(_ profile: Profile) -> some View {
        let isActive = profile.id == profileManager.activeProfileId
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailHeader(profile, isActive: isActive)
                Divider()
                CurveEditorView(
                    profile: Binding(
                        get: { profile },
                        set: { commit($0) }
                    ),
                    sensorKeys: fanController.sensors.map(\.id),
                    fans: fanController.fans
                )
                .disabled(profile.isPreset)
                .opacity(profile.isPreset ? 0.7 : 1.0)

                if !profile.isPreset {
                    Divider()
                    TriggersEditorView(
                        profile: Binding(
                            get: { profile },
                            set: { commit($0) }
                        )
                    )
                }
            }
            .padding(24)
        }
    }

    private func detailHeader(_ profile: Profile, isActive: Bool) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: profile.icon)
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                if profile.isPreset {
                    HStack(spacing: 8) {
                        Text(profile.name).font(.title2.bold())
                        Text("Preset").font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TextField("Profile Name", text: Binding(
                        get: { profile.name },
                        set: { newName in
                            var updated = profile
                            updated.name = newName
                            commit(updated)
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                }
                Text(profile.isPreset ? "Read-only fan curve" : "Custom profile — edit freely")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            } else {
                Button {
                    profileManager.activeProfileId = profile.id
                } label: {
                    Label("Activate", systemImage: "play.fill")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }

            if !profile.isPreset {
                Button(role: .destructive) {
                    profileToDelete = profile
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.large)
            }
        }
    }

    private func commit(_ profile: Profile) {
        guard !profile.isPreset else { return }
        var sanitized = profile
        let trimmed = sanitized.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { sanitized.name = "Untitled Profile" } else { sanitized.name = trimmed }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                try profileManager.saveCustomProfile(sanitized)
            } catch is CancellationError {
                return
            } catch {
                operationError = error.localizedDescription
            }
        }
    }
}

struct TriggersEditorView: View {
    @Binding var profile: Profile
    @State private var newAppBundleId = ""

    private var triggers: [ProfileTrigger] { profile.triggers ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Auto-Activation Triggers").font(.headline)
                Text("(any match)").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Text("This profile activates automatically when any trigger matches. Frontmost-app triggers beat thermal-state triggers, which beat power-source triggers.")
                .font(.caption).foregroundStyle(.secondary)

            if triggers.isEmpty {
                Text("No triggers — profile activates only manually.")
                    .font(.caption).foregroundStyle(.tertiary).italic()
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(triggers.enumerated()), id: \.offset) { index, trigger in
                    HStack {
                        Image(systemName: iconName(for: trigger))
                            .foregroundStyle(.tint).frame(width: 20)
                        Text(label(for: trigger))
                        Spacer()
                        Button(role: .destructive) {
                            var t = triggers
                            t.remove(at: index)
                            profile.triggers = t.isEmpty ? nil : t
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack(spacing: 8) {
                Menu {
                    Section("Power Source") {
                        Button("On AC Power") { add(.powerSource(.ac)) }
                        Button("On Battery") { add(.powerSource(.battery)) }
                    }
                    Section("Thermal State") {
                        Button("Nominal") { add(.thermalState(.nominal)) }
                        Button("Fair") { add(.thermalState(.fair)) }
                        Button("Serious") { add(.thermalState(.serious)) }
                        Button("Critical") { add(.thermalState(.critical)) }
                    }
                } label: {
                    Label("Add Trigger", systemImage: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 140)

                TextField("App bundle id (e.g. com.apple.Xcode)", text: $newAppBundleId)
                    .textFieldStyle(.roundedBorder)
                Button("Add App") {
                    let trimmed = newAppBundleId.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    add(.frontmostApp(bundleId: trimmed))
                    newAppBundleId = ""
                }
                .disabled(newAppBundleId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func add(_ trigger: ProfileTrigger) {
        var t = triggers
        if !t.contains(trigger) { t.append(trigger) }
        profile.triggers = t
    }

    private func iconName(for trigger: ProfileTrigger) -> String {
        switch trigger {
        case .powerSource(.ac): return "powerplug"
        case .powerSource(.battery): return "battery.100"
        case .thermalState: return "thermometer"
        case .frontmostApp: return "app"
        }
    }

    private func label(for trigger: ProfileTrigger) -> String {
        switch trigger {
        case .powerSource(.ac): return "On AC Power"
        case .powerSource(.battery): return "On Battery"
        case .thermalState(let level): return "Thermal: \(level.rawValue.capitalized)"
        case .frontmostApp(let bid): return "App is frontmost: \(bid)"
        }
    }
}
