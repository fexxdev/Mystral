import Foundation

/// The language Mystral's UI uses.
///
/// `.system` follows macOS. The other cases override it for Mystral only, through the
/// app's own `AppleLanguages` preference: the same key System Settings → Language &
/// Region → Applications writes, so the two stay in agreement. macOS reads it at launch,
/// so a change takes effect after a restart.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = ""
    case english = "en"
    case italian = "it"
    case simplifiedChinese = "zh-Hans"

    static let defaultsKey = "AppleLanguages"

    var id: String { rawValue }

    /// Each language's name written in that language, so people can find theirs
    /// whatever language the UI is currently in. Empty for `.system`, which is localized.
    var nativeName: String {
        switch self {
        case .system: ""
        case .english: "English"
        case .italian: "Italiano"
        case .simplifiedChinese: "简体中文"
        }
    }

    /// The override stored for this app, or `.system` when there is none or it names a
    /// language Mystral doesn't ship. Reads only the app's own domain: `defaults.array`
    /// would also return the global macOS language list.
    static func current(
        in defaults: UserDefaults = .standard,
        domain: String? = Bundle.main.bundleIdentifier
    ) -> AppLanguage {
        guard let domain,
              let first = (defaults.persistentDomain(forName: domain)?[defaultsKey] as? [String])?.first
        else { return .system }
        return allCases.first { language in
            language != .system && (first == language.rawValue || first.hasPrefix(language.rawValue + "-"))
        } ?? .system
    }

    func apply(to defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set([rawValue], forKey: Self.defaultsKey)
        }
    }
}
