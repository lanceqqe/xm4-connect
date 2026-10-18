import Foundation

/// Interface language. "System" follows macOS (French if French is preferred, otherwise English).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, french

    var id: String { rawValue }

    /// Shown in its own language so it is recognisable whatever the current one is.
    var displayName: String {
        switch self {
        case .system: return L("Automatic", "Automatique")
        case .english: return "English"
        case .french: return "Français"
        }
    }
}

enum Localization {
    nonisolated(unsafe) private(set) static var isFrench: Bool = systemPrefersFrench

    static var systemPrefersFrench: Bool {
        (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("fr")
    }

    static func apply(_ language: AppLanguage) {
        switch language {
        case .system: isFrench = systemPrefersFrench
        case .english: isFrench = false
        case .french: isFrench = true
        }
    }
}

/// Every user-facing string is written in both languages at its call site:
/// `L("Noise cancelling", "Réduction de bruit")`. No keys to keep in sync, nothing to miss.
func L(_ english: String, _ french: String) -> String {
    Localization.isFrench ? french : english
}
