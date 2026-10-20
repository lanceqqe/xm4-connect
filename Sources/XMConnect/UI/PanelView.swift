import AppKit
import SwiftUI
import SonyProtocolKit

/// Shared between the menu bar controller and SwiftUI: whether the panel is on screen.
@MainActor
final class PanelState: ObservableObject {
    @Published var isVisible = false
    @Published var tab: PanelTab = .listening
}

struct PanelView: View {
    @ObservedObject var model: HeadphonesModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: PanelState
    var onQuit: () -> Void

    @State var confirmPowerOff = false

    private var look: ListeningLook { ListeningLook(mode: model.mode, connected: model.isConnected) }

    var body: some View {
        ZStack {
            PanelBackground(look: look)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                modeHeader
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                VStack(spacing: 12) {
                    ModeSelector(model: model, look: look)
                    TabBar(selection: $state.tab, look: look)
                    tabContent
                        .frame(height: 214, alignment: .top)
                }
                .padding(.horizontal, 16)
                // Rebuild the controls when the language changes so every label updates.
                .id(settings.language)
                footer
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .id(settings.language)
            }
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .scaleEffect(state.isVisible ? 1 : 0.94, anchor: .top)
        .opacity(state.isVisible ? 1 : 0)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: state.isVisible)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName)
                    .font(.rounded(17, .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StatusDot(connected: model.isConnected, connecting: model.isConnecting, look: look)
                    Text(model.statusText)
                        .font(.rounded(11.5, .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .id(model.statusText)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .animation(.easeInOut(duration: 0.25), value: model.statusText)
            }
            Spacer()
            if model.isConnected {
                BatteryRing(level: model.batteryLevel, charging: model.isCharging, look: look)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4), value: model.isConnected)
    }

    // MARK: Mode

    /// The current mode: a gradient badge, its name and a one-line description. Clicking it
    /// moves to the next mode, like the NC/AMB button on the headset.
    private var modeHeader: some View {
        Button(action: cycleMode) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.gradient(look))
                    Image(systemName: modeIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(look.title)
                        .font(.rounded(17, .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(look.subtitle)
                        .font(.rounded(11.5, .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Click to change mode", "Clique pour changer de mode"))
        .animation(.easeInOut(duration: 0.2), value: look)
    }

    private var modeIcon: String {
        switch look {
        case .noiseCancelling: return "shield.lefthalf.filled"
        case .wind: return "wind"
        case .ambient: return "ear"
        case .off: return "circle.slash"
        case .disconnected: return "headphones"
        }
    }

    // MARK: Tabs

    @ViewBuilder
    private var tabContent: some View {
        ZStack(alignment: .top) {
            switch state.tab {
            case .listening:
                ListeningTab(model: model, look: look)
                    .transition(tabTransition)
            case .equalizer:
                EqualizerView(model: model, look: look)
                    .transition(tabTransition)
            case .options:
                OptionsTab(model: model, settings: settings, look: look)
                    .transition(tabTransition)
            }
        }
    }

    private var tabTransition: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if model.isConnected && model.powerOffVisible {
                if confirmPowerOff {
                    PillButton(icon: "power", title: L("Turn off?", "Éteindre ?"), filled: Color(red: 0.9, green: 0.25, blue: 0.3)) {
                        confirmPowerOff = false
                        model.powerOff()
                        Haptics.click()
                    }
                    .transition(.scale.combined(with: .opacity))
                    PillButton(icon: "xmark", title: L("Cancel", "Annuler")) { confirmPowerOff = false }
                        .transition(.opacity)
                } else {
                    PillButton(icon: "power", title: L("Turn off headphones", "Éteindre le casque")) {
                        confirmPowerOff = true
                        // Drop the confirmation if it is not used.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { confirmPowerOff = false }
                    }
                    .transition(.opacity)
                }
            }
            Spacer()
            Menu {
                Button(model.isDemo ? L("Use the real headphones", "Utiliser le vrai casque") : L("Demo mode", "Mode démo")) {
                    NotificationCenter.default.post(name: .toggleDemo, object: nil)
                }
                Button(L("Open the log", "Ouvrir le journal")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: Log.path))
                }
                Divider()
                Button(L("Quit XM4 Connect", "Quitter XM4 Connect"), action: onQuit)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .animation(.spring(response: 0.3), value: confirmPowerOff)
    }

    private func cycleMode() {
        guard model.isConnected, model.hasNoiseControls else { return }
        let order = model.availableModes
        let index = order.firstIndex(of: model.mode) ?? 0
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
            model.mode = order[(index + 1) % order.count]
        }
        Haptics.click()
    }
}

extension Notification.Name {
    static let toggleDemo = Notification.Name("XMConnectToggleDemo")
    static let applyConnectVolume = Notification.Name("XMConnectApplyConnectVolume")
}

/// Connection dot.
struct StatusDot: View {
    let connected: Bool
    let connecting: Bool
    let look: ListeningLook

    var body: some View {
        let color: Color = connected ? Color(red: 0.3, green: 0.9, blue: 0.55)
            : (connecting ? look.accent.0.color : Color(red: 1, green: 0.45, blue: 0.4))
        Circle().fill(color).frame(width: 7, height: 7)
            .frame(width: 10, height: 10)
    }
}

/// Dark glass with a soft, static tint of the current mode's colour at the top.
struct PanelBackground: View {
    var look: ListeningLook

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.07, blue: 0.10).opacity(0.80),
                                    Color(red: 0.03, green: 0.03, blue: 0.05).opacity(0.90)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [look.accent.0.color.opacity(0.22), .clear],
                           startPoint: .top, endPoint: .center)
                .animation(.easeInOut(duration: 0.4), value: look)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
