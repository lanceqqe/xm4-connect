import AppKit
import SwiftUI
import SonyProtocolKit

/// Shared between the menu bar controller and SwiftUI: whether the panel is on screen, so the
/// 3D scene and the animated background only render while visible.
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

    @State var nudge = 0
    @State var confirmPowerOff = false

    private var look: ListeningLook { ListeningLook(mode: model.mode, connected: model.isConnected) }

    var body: some View {
        ZStack {
            AppBackground(look: look, animating: state.isVisible && !settings.reduceMotion)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                hero
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

    // MARK: Hero (3D)

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            HeadphonesSceneView(
                target: HeadphonesSceneController.Target(
                    look: look,
                    level: Float((model.ambientLevel - 1) / 19),
                    focusOnVoice: model.focusOnVoice,
                    finish: settings.finish,
                    reduceMotion: settings.reduceMotion),
                isActive: state.isVisible,
                nudge: nudge,
                onTap: cycleMode)
                .frame(height: 206)
                .help(L("Drag to spin · Click to change mode", "Glisse pour faire tourner · Clique pour changer de mode"))

            VStack(alignment: .leading, spacing: 2) {
                Text(look.title)
                    .font(.rounded(20, .heavy))
                    .foregroundStyle(Theme.gradient(look))
                Text(look.subtitle)
                    .font(.rounded(11.5, .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .id(look)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity))
            .padding(.leading, 20)
            .padding(.bottom, 8)
            .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: look)
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
                EqualizerView(model: model, look: look, onPresetChange: { nudge += 1 })
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
}

/// Pulsing connection dot.
struct StatusDot: View {
    let connected: Bool
    let connecting: Bool
    let look: ListeningLook
    @State var pulse = false

    var body: some View {
        let color: Color = connected ? Color(red: 0.3, green: 0.9, blue: 0.55)
            : (connecting ? look.accent.0.color : Color(red: 1, green: 0.45, blue: 0.4))
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 14, height: 14)
                .scaleEffect(pulse ? 1 : 0.4)
                .opacity(pulse ? 0 : 1)
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Dark glass with slowly drifting, blurred colour blobs tinted by the current mode.
struct AppBackground: View {
    var look: ListeningLook
    var animating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(colors: [Color(red: 0.07, green: 0.07, blue: 0.10).opacity(0.72),
                                        Color(red: 0.03, green: 0.03, blue: 0.05).opacity(0.86)],
                               startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(look.accent.0.color)
                    .frame(width: 260, height: 260)
                    .offset(x: CGFloat(cos(t * 0.23) * 70 - 60), y: CGFloat(sin(t * 0.31) * 40 - 190))
                    .blur(radius: 80)
                    .opacity(0.45)
                Circle()
                    .fill(look.accent.1.color)
                    .frame(width: 220, height: 220)
                    .offset(x: CGFloat(sin(t * 0.19) * 80 + 80), y: CGFloat(cos(t * 0.27) * 50 - 90))
                    .blur(radius: 80)
                    .opacity(0.38)
                Circle()
                    .fill(look.accent.0.color)
                    .frame(width: 200, height: 200)
                    .offset(x: CGFloat(cos(t * 0.17) * 60), y: CGFloat(sin(t * 0.21) * 40 + 230))
                    .blur(radius: 90)
                    .opacity(0.22)
            }
            .animation(.easeInOut(duration: 0.8), value: look)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        )
    }
}
