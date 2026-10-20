import AppKit
import SwiftUI
import SonyProtocolKit
import simd

/// One colour, usable from SwiftUI and AppKit.
struct RGB: Equatable {
    var r: Double, g: Double, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    var simd: SIMD3<Float> { SIMD3(Float(r), Float(g), Float(b)) }
}

/// What the scene and the controls show: one of the listening modes, or "not connected".
enum ListeningLook: Equatable {
    case noiseCancelling, wind, ambient, off, disconnected

    init(mode: NcAmbMode, connected: Bool) {
        guard connected else { self = .disconnected; return }
        switch mode {
        case .noiseCancelling: self = .noiseCancelling
        case .windNoiseReduction: self = .wind
        case .ambient: self = .ambient
        case .off: self = .off
        }
    }

    /// Two-stop accent gradient.
    var accent: (RGB, RGB) {
        switch self {
        case .noiseCancelling: return (RGB(hex: 0x6C63FF), RGB(hex: 0x2FD2FF))
        case .wind: return (RGB(hex: 0x1FC8A8), RGB(hex: 0x6FE3FF))
        case .ambient: return (RGB(hex: 0xFFB13B), RGB(hex: 0xFF5E9C))
        case .off: return (RGB(hex: 0xB8C0CC), RGB(hex: 0x8792A2))
        case .disconnected: return (RGB(hex: 0x5D6470), RGB(hex: 0x3A3F48))
        }
    }

    var title: String {
        switch self {
        case .noiseCancelling: return L("Noise cancelling", "Réduction de bruit")
        case .wind: return L("Wind noise reduction", "Réduction du bruit du vent")
        case .ambient: return L("Ambient sound", "Son ambiant")
        case .off: return L("Off", "Désactivé")
        case .disconnected: return L("Not connected", "Non connecté")
        }
    }

    var subtitle: String {
        switch self {
        case .noiseCancelling: return L("The world fades away", "Le monde extérieur s'efface")
        case .wind: return L("Calm sound outdoors, even in a gust", "Un son calme dehors, même par grand vent")
        case .ambient: return L("Hear what's around you", "Tu entends ce qui t'entoure")
        case .off: return L("Natural sound, no processing", "Son naturel, sans traitement")
        case .disconnected: return L("Turn the headphones on and connect them", "Allume le casque et connecte-le")
        }
    }
}

enum Theme {
    static func gradient(_ look: ListeningLook) -> LinearGradient {
        LinearGradient(colors: [look.accent.0.color, look.accent.1.color],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let panelWidth: CGFloat = 372
    static let panelHeight: CGFloat = 520
    static let corner: CGFloat = 26
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.36)
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.09)
}

/// Small persisted preferences.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var showBatteryInMenuBar: Bool {
        didSet { defaults.set(showBatteryInMenuBar, forKey: "showBatteryInMenuBar") }
    }

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            Localization.apply(language)
        }
    }

    /// Set the Mac's volume for the headphones each time they connect.
    @Published var volumeOnConnect: Bool {
        didSet { defaults.set(volumeOnConnect, forKey: "volumeOnConnect") }
    }

    /// 0…1.
    @Published var connectVolume: Double {
        didSet { defaults.set(connectVolume, forKey: "connectVolume") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            let actual = LaunchAtLogin.set(launchAtLogin)
            if actual != launchAtLogin { launchAtLogin = actual }
        }
    }

    init() {
        // A local: `self.defaults` cannot be read before every property is initialised.
        let defaults = UserDefaults.standard
        showBatteryInMenuBar = defaults.object(forKey: "showBatteryInMenuBar") as? Bool ?? true
        launchAtLogin = LaunchAtLogin.isEnabled
        volumeOnConnect = defaults.object(forKey: "volumeOnConnect") as? Bool ?? true
        connectVolume = defaults.object(forKey: "connectVolume") as? Double ?? 0.6
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        Localization.apply(language)
    }
}
