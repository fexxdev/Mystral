import Foundation
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "ProfileManager")

enum ProfileError: Error, LocalizedError {
    case maxProfilesReached
    case profileNotFound

    var errorDescription: String? {
        switch self {
        case .maxProfilesReached: "Maximum of 10 custom profiles reached"
        case .profileNotFound: "Profile not found"
        }
    }
}

@Observable
final class ProfileManager {
    static let maxCustomProfiles = 10
    private static let activeProfileKey = "activeProfileId"

    private(set) var presets: [Profile] = []
    private(set) var customProfiles: [Profile] = []
    var activeProfileId: UUID? {
        didSet {
            let name = allProfiles.first { $0.id == activeProfileId }?.name ?? "nil"
            logger.info("activeProfileId changed to \(name, privacy: .public) (\(self.activeProfileId?.uuidString ?? "nil", privacy: .public))")
            if let id = activeProfileId {
                UserDefaults.standard.set(id.uuidString, forKey: Self.activeProfileKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.activeProfileKey)
            }
        }
    }

    private let storageDirectory: URL

    var activeProfile: Profile? {
        allProfiles.first { $0.id == activeProfileId }
    }

    var allProfiles: [Profile] { presets + customProfiles }

    init(storageDirectory: URL? = nil) {
        let dir = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mystral").appendingPathComponent("profiles")
        self.storageDirectory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        loadPresets()
        loadCustomProfiles()
        if let saved = UserDefaults.standard.string(forKey: Self.activeProfileKey),
           let uuid = UUID(uuidString: saved),
           allProfiles.contains(where: { $0.id == uuid }) {
            activeProfileId = uuid
        } else {
            activeProfileId = presets.first { $0.name == "Balanced" }?.id ?? presets.first?.id
        }
        logger.info("ProfileManager init — presets=\(self.presets.count, privacy: .public), custom=\(self.customProfiles.count, privacy: .public), active=\(self.activeProfile?.name ?? "nil", privacy: .public)")
    }

    private func loadPresets() {
        let presetNames = ["silent", "balanced", "performance", "fullblast"]
        let decoder = JSONDecoder()
        presets = presetNames.compactMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Presets"),
                  let data = try? Data(contentsOf: url),
                  var profile = try? decoder.decode(Profile.self, from: data) else {
                return loadFallbackPreset(name: name)
            }
            profile.isPreset = true
            return profile
        }
    }

    private func loadFallbackPreset(name: String) -> Profile? {
        switch name {
        case "silent":
            return Profile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Silent", icon: "speaker.slash", isPreset: true,
                           curvePoints: [CurvePoint(temperature: 30, fanPercentage: 10), CurvePoint(temperature: 50, fanPercentage: 20),
                                         CurvePoint(temperature: 70, fanPercentage: 40), CurvePoint(temperature: 85, fanPercentage: 60),
                                         CurvePoint(temperature: 95, fanPercentage: 80)])
        case "balanced":
            return Profile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Balanced", icon: "dial.medium", isPreset: true,
                           curvePoints: [CurvePoint(temperature: 30, fanPercentage: 15), CurvePoint(temperature: 50, fanPercentage: 30),
                                         CurvePoint(temperature: 65, fanPercentage: 50), CurvePoint(temperature: 80, fanPercentage: 75),
                                         CurvePoint(temperature: 95, fanPercentage: 100)])
        case "performance":
            return Profile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Performance", icon: "hare", isPreset: true,
                           curvePoints: [CurvePoint(temperature: 30, fanPercentage: 25), CurvePoint(temperature: 45, fanPercentage: 45),
                                         CurvePoint(temperature: 60, fanPercentage: 70), CurvePoint(temperature: 75, fanPercentage: 90),
                                         CurvePoint(temperature: 85, fanPercentage: 100)])
        case "fullblast":
            return Profile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Full Blast", icon: "wind", isPreset: true,
                           curvePoints: [CurvePoint(temperature: 0, fanPercentage: 100)])
        default: return nil
        }
    }

    private func loadCustomProfiles() {
        let decoder = JSONDecoder()
        guard let files = try? FileManager.default.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else { return }
        customProfiles = files.compactMap { url in
            do {
                let data = try Data(contentsOf: url)
                let profile = try decoder.decode(Profile.self, from: data)
                guard !profile.isPreset else { return nil }
                return profile
            } catch {
                logger.error("Failed to load profile \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    func saveCustomProfile(_ profile: Profile) throws {
        let data = try JSONEncoder().encode(profile)
        let url = storageDirectory.appendingPathComponent("\(profile.id.uuidString).json")

        if let index = customProfiles.firstIndex(where: { $0.id == profile.id }) {
            try data.write(to: url, options: .atomic)
            customProfiles[index] = profile
        } else {
            guard customProfiles.count < Self.maxCustomProfiles else { throw ProfileError.maxProfilesReached }
            try data.write(to: url, options: .atomic)
            customProfiles.append(profile)
        }
    }

    func deleteCustomProfile(id: UUID) throws {
        guard let index = customProfiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.profileNotFound }
        let url = storageDirectory.appendingPathComponent("\(id.uuidString).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        customProfiles.remove(at: index)
        if activeProfileId == id { activeProfileId = presets.first { $0.name == "Balanced" }?.id }
    }

    func duplicateAsCustom(_ preset: Profile) throws -> Profile {
        let copy = Profile(name: "\(preset.name) (Custom)", icon: preset.icon, isPreset: false,
                           curvePoints: preset.curvePoints, sensorKey: preset.sensorKey)
        try saveCustomProfile(copy)
        return copy
    }
}
