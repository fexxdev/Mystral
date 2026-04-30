import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "UpdateChecker")

@Observable
@MainActor
final class UpdateChecker {

    enum Status: Equatable {
        case unknown
        case checking
        case upToDate
        case updateAvailable(version: String, releaseURL: URL, dmgURL: URL?, notes: String)
        case error(String)
    }

    private static let autoCheckKey = "updatesAutoCheckEnabled"
    private static let lastCheckedKey = "updatesLastCheckedAt"
    private static let releasesURL = URL(string: "https://api.github.com/repos/fexxdev/Mystral/releases/latest")!
    private static let minAutoCheckInterval: TimeInterval = 60 * 60 * 24

    var status: Status = .unknown
    var lastCheckedAt: Date?
    var autoCheckEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCheckEnabled, forKey: Self.autoCheckKey) }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    init() {
        if UserDefaults.standard.object(forKey: Self.autoCheckKey) != nil {
            self.autoCheckEnabled = UserDefaults.standard.bool(forKey: Self.autoCheckKey)
        } else {
            self.autoCheckEnabled = true
        }
        if let stored = UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Date {
            self.lastCheckedAt = stored
        }
    }

    func runAutoCheckIfNeeded() {
        guard autoCheckEnabled else { return }
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < Self.minAutoCheckInterval {
            return
        }
        Task { await checkForUpdates(silent: true) }
    }

    func checkForUpdates(silent: Bool = false) async {
        if !silent { status = .checking }
        do {
            var request = URLRequest(url: Self.releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Mystral/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tag_name.hasPrefix("v")
                ? String(release.tag_name.dropFirst())
                : release.tag_name

            lastCheckedAt = Date()
            UserDefaults.standard.set(lastCheckedAt, forKey: Self.lastCheckedKey)

            if Self.compareVersions(latestVersion, currentVersion) == .orderedDescending {
                let dmgURL = release.assets.first(where: { $0.name.hasSuffix(".dmg") }).flatMap { URL(string: $0.browser_download_url) }
                let pageURL = URL(string: release.html_url) ?? Self.releasesURL
                status = .updateAvailable(version: latestVersion, releaseURL: pageURL, dmgURL: dmgURL, notes: release.body ?? "")
                logger.info("Update available: \(latestVersion, privacy: .public)")
            } else {
                status = .upToDate
                logger.info("Up to date (current \(self.currentVersion, privacy: .public), latest \(latestVersion, privacy: .public))")
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            if !silent {
                status = .error(error.localizedDescription)
            }
        }
    }

    func openReleasePage() {
        if case .updateAvailable(_, let url, _, _) = status {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/fexxdev/Mystral/releases")!)
        }
    }

    nonisolated static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let count = max(aParts.count, bParts.count)
        for i in 0..<count {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return .orderedSame
    }

    private enum UpdateError: LocalizedError {
        case badResponse(Int)
        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "GitHub returned status \(code)"
            }
        }
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }
}
