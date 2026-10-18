import SwiftUI
import SonyProtocolKit

enum PanelTab: String, CaseIterable, Identifiable {
    case listening, equalizer, options
    var id: String { rawValue }

    var title: String {
        switch self {
        case .listening: return L("Listening", "Écoute")
        case .equalizer: return L("Equalizer", "Égaliseur")
        case .options: return L("Options", "Options")
        }
    }

    var icon: String {
        switch self {
        case .listening: return "waveform"
        case .equalizer: return "slider.vertical.3"
        case .options: return "gearshape"
        }
    }
}

/// Segmented tab bar with a sliding highlight.
struct TabBar: View {
    @Binding var selection: PanelTab
    var look: ListeningLook
    @Namespace var highlight

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases) { tab in
                let selected = tab == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 10.5, weight: .semibold))
                        Text(tab.title).font(.rounded(12, .semibold))
                    }
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .overlay(
                                    Capsule()
                                        .fill(Theme.gradient(look))
                                        .frame(height: 2)
                                        .padding(.horizontal, 18)
                                        .offset(y: 13)
                                        .shadow(color: look.accent.1.color, radius: 4)
                                )
                                .matchedGeometryEffect(id: "tab", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.22)))
    }
}

/// Ambient level, Focus on Voice, Speak-to-Chat and pause on removal.
struct ListeningTab: View {
    @ObservedObject var model: HeadphonesModel
    var look: ListeningLook

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            OptionLabel(icon: "dial.medium",
                                        title: L("Ambient sound level", "Niveau du son ambiant"),
                                        detail: model.mode == .ambient ? nil : L("Active in Ambient mode", "Actif en mode Ambiant"))
                            Spacer()
                            Text("\(Int(model.ambientLevel))")
                                .font(.rounded(20, .bold))
                                .monospacedDigit()
                                .foregroundStyle(model.ambientControlsEnabled ? AnyShapeStyle(Theme.gradient(look)) : AnyShapeStyle(Theme.textTertiary))
                                .frame(minWidth: 30, alignment: .trailing)
                                .animation(.spring(response: 0.3), value: model.ambientLevel)
                        }
                        GlowSlider(value: $model.ambientLevel, range: 1...20,
                                   look: model.ambientControlsEnabled ? look : .off,
                                   enabled: model.ambientControlsEnabled)
                        Toggle(isOn: $model.focusOnVoice) {
                            OptionLabel(icon: "person.wave.2", title: L("Focus on voice", "Focus sur la voix"),
                                        detail: L("Lets voices through, softens the rest", "Laisse passer les voix, atténue le reste"))
                        }
                        .toggleStyle(GlowToggleStyle(look: look))
                        .disabled(!model.ambientControlsEnabled)
                        .opacity(model.ambientControlsEnabled ? 1 : 0.45)
                    }
                }
                if model.hasSpeakToChat {
                    Card {
                        Toggle(isOn: $model.speakToChat) {
                            OptionLabel(icon: "bubble.left.and.bubble.right", title: "Speak-to-Chat",
                                        detail: L("Pauses the music when you talk", "Met la musique en pause quand tu parles"))
                        }
                        .toggleStyle(GlowToggleStyle(look: look))
                        .disabled(!model.isConnected)
                    }
                }
                if model.showsAutoPause {
                    Card {
                        VStack(spacing: 12) {
                            Toggle(isOn: $model.autoPause) {
                                OptionLabel(icon: "pause.circle", title: L("Pause when taken off", "Pause quand je le retire"),
                                            detail: wearingDetail)
                            }
                            .toggleStyle(GlowToggleStyle(look: look))
                            if model.autoPause && model.hasWearingStatus {
                                Toggle(isOn: $model.resumeOnWear) {
                                    OptionLabel(icon: "play.circle", title: L("Resume when put back on", "Reprendre quand je le remets"))
                                }
                                .toggleStyle(GlowToggleStyle(look: look))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                            if model.isDemo {
                                HStack(spacing: 8) {
                                    PillButton(icon: "arrow.up.circle", title: L("Take off", "Retirer")) {
                                        model.simulateWearing(.removed)
                                    }
                                    PillButton(icon: "arrow.down.circle", title: L("Put on", "Remettre")) {
                                        model.simulateWearing(.worn)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: model.autoPause)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var wearingDetail: String {
        switch model.wearing {
        case .worn: return L("Sensor: on your head", "Capteur : sur tes oreilles")
        case .removed: return L("Sensor: taken off", "Capteur : retiré")
        case .unknown:
            return model.hasWearingStatus
                ? L("Waiting for the sensor…", "En attente du capteur…")
                : L("Handled by the headphones", "Géré par le casque")
        }
    }
}

/// Headset options and app preferences.
struct OptionsTab: View {
    @ObservedObject var model: HeadphonesModel
    @ObservedObject var settings: AppSettings
    var look: ListeningLook

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                if model.hasDsee || model.hasAutoPowerOff {
                    Card {
                        VStack(spacing: 12) {
                            if model.hasDsee {
                                Toggle(isOn: $model.dsee) {
                                    OptionLabel(icon: "sparkles", title: "DSEE Extreme",
                                                detail: L("Restores detail in compressed music", "Restaure les détails des fichiers compressés"))
                                }
                                .toggleStyle(GlowToggleStyle(look: look))
                            }
                            if model.hasAutoPowerOff {
                                HStack {
                                    OptionLabel(icon: "timer", title: L("Auto power off", "Arrêt automatique"))
                                    Spacer()
                                    ChoiceMenu(
                                        current: HeadphonesModel.name(of: model.autoPowerOff),
                                        choices: model.autoPowerOffChoices.map { ($0.rawValue, HeadphonesModel.name(of: $0)) },
                                        selected: model.autoPowerOff.rawValue
                                    ) { raw in model.autoPowerOff = AutoPowerOff(rawValue: raw) }
                                }
                            }
                        }
                        .disabled(!model.isConnected)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        OptionLabel(icon: "paintpalette", title: L("3D headphones finish", "Finition du casque 3D"))
                        HStack(spacing: 10) {
                            ForEach(HeadsetFinish.allCases) { finish in
                                FinishSwatch(finish: finish, selected: settings.finish == finish, look: look) {
                                    withAnimation(.spring(response: 0.3)) { settings.finish = finish }
                                    Haptics.click()
                                }
                            }
                        }
                        .padding(.leading, 32)
                    }
                }

                Card {
                    VStack(spacing: 12) {
                        HStack {
                            OptionLabel(icon: "globe", title: L("Language", "Langue"))
                            Spacer()
                            ChoiceMenu(
                                current: settings.language.displayName,
                                choices: AppLanguage.allCases.map { ($0.rawValue, $0.displayName) },
                                selected: settings.language.rawValue
                            ) { raw in
                                if let language = AppLanguage(rawValue: raw) { settings.language = language }
                            }
                        }
                        Toggle(isOn: $settings.showBatteryInMenuBar) {
                            OptionLabel(icon: "battery.75", title: L("Battery in the menu bar", "Batterie dans la barre des menus"))
                        }
                        .toggleStyle(GlowToggleStyle(look: look))
                        Toggle(isOn: $settings.launchAtLogin) {
                            OptionLabel(icon: "power.circle", title: L("Open at login", "Ouvrir au démarrage du Mac"))
                        }
                        .toggleStyle(GlowToggleStyle(look: look))
                        Toggle(isOn: $settings.reduceMotion) {
                            OptionLabel(icon: "figure.walk.motion", title: L("Reduce motion", "Réduire les animations"))
                        }
                        .toggleStyle(GlowToggleStyle(look: look))
                    }
                }

                Text(L("XM Connect is not affiliated with Sony. Protocol from the open-source projects sony-tray and SonyHeadphonesClient.",
                       "XM Connect n'est pas affilié à Sony. Protocole issu des projets open source sony-tray et SonyHeadphonesClient."))
                    .font(.rounded(9.5))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
            }
            .padding(.bottom, 8)
        }
    }
}

/// Compact pop-up menu showing the current choice as a pill.
struct ChoiceMenu<ID: Hashable>: View {
    let current: String
    let choices: [(ID, String)]
    let selected: ID
    let onSelect: (ID) -> Void

    var body: some View {
        Menu {
            ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                Button {
                    onSelect(choice.0)
                } label: {
                    if choice.0 == selected {
                        Label(choice.1, systemImage: "checkmark")
                    } else {
                        Text(choice.1)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.rounded(12, .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct FinishSwatch: View {
    let finish: HeadsetFinish
    let selected: Bool
    let look: ListeningLook
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(
                        RadialGradient(colors: [finish.body.color.opacity(0.85), finish.body.color, finish.cushion.color],
                                       center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 16)
                    )
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                    .padding(3)
                    .overlay(
                        Circle().strokeBorder(selected ? AnyShapeStyle(Theme.gradient(look)) : AnyShapeStyle(Color.clear),
                                              lineWidth: 2)
                    )
                    .scaleEffect(selected ? 1.08 : 1)
                Text(finish.name)
                    .font(.rounded(9.5, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
