import SwiftUI
import SonyProtocolKit

/// Big tiles: Noise cancelling / Wind / Ambient / Off. The selected tile carries the mode
/// gradient, which slides between tiles; hovering tilts a tile in 3D toward the pointer.
struct ModeSelector: View {
    @ObservedObject var model: HeadphonesModel
    var look: ListeningLook
    @Namespace var selection

    private struct Item: Identifiable {
        let mode: NcAmbMode
        let icon: String
        let title: String
        var id: String { title }
    }

    private var items: [Item] {
        // Four tiles share the width on the XM4, so the noise-cancelling label gets shorter.
        let compact = model.availableModes.count > 3
        return model.availableModes.map { mode in
            switch mode {
            case .noiseCancelling:
                return Item(mode: mode, icon: "shield.lefthalf.filled",
                            title: compact ? L("NC", "Anti-bruit") : L("Noise Canceling", "Anti-bruit"))
            case .windNoiseReduction:
                return Item(mode: mode, icon: "wind", title: L("Wind", "Vent"))
            case .ambient:
                return Item(mode: mode, icon: "ear", title: L("Ambient", "Ambiant"))
            case .off:
                return Item(mode: mode, icon: "circle.slash", title: L("Off", "Désactivé"))
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                ModeTile(item: item.mode, icon: item.icon, title: item.title,
                         selected: model.isConnected && model.mode == item.mode,
                         look: ListeningLook(mode: item.mode, connected: true),
                         namespace: selection) {
                    guard model.isConnected, model.hasNoiseControls, model.mode != item.mode else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                        model.mode = item.mode
                    }
                    Haptics.click()
                }
            }
        }
        .disabled(!model.isConnected || !model.hasNoiseControls)
        .opacity(model.isConnected ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.25), value: model.isConnected)
    }
}

private struct ModeTile: View {
    let item: NcAmbMode
    let icon: String
    let title: String
    let selected: Bool
    let look: ListeningLook
    let namespace: Namespace.ID
    let action: () -> Void

    @State var hover: CGPoint?
    @State var pressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if selected {
                        Circle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 34, height: 34)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                        .scaleEffect(selected ? 1.12 : 1)
                }
                .frame(height: 34)
                Text(title)
                    .font(.rounded(11.5, .semibold))
                    .foregroundStyle(selected ? Color.white : Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(hover == nil ? 0.05 : 0.09))
                    if selected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.gradient(look))
                            .shadow(color: look.accent.1.color.opacity(0.55), radius: 14, y: 6)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                        // Specular sheen that follows the pointer.
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(RadialGradient(colors: [Color.white.opacity(0.35), .clear],
                                                 center: sheenCenter, startRadius: 0, endRadius: 70))
                            .blendMode(.plusLighter)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.25 : 0.07), lineWidth: 1)
            )
            .rotation3DEffect(.degrees(tilt.x), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(tilt.y), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .scaleEffect(pressed ? 0.95 : (hover == nil ? 1 : 1.03))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressReporter(pressed: $pressed))
        .onContinuousHover { phase in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                switch phase {
                case .active(let location): hover = location
                case .ended: hover = nil
                }
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
    }

    /// Degrees of tilt toward the pointer (tile is ~110 × 74 pt).
    private var tilt: (x: Double, y: Double) {
        guard let hover else { return (0, 0) }
        let nx = Double(hover.x / 110) - 0.5
        let ny = Double(hover.y / 74) - 0.5
        return (x: ny * -14, y: nx * 16)
    }

    private var sheenCenter: UnitPoint {
        guard let hover else { return UnitPoint(x: 0.3, y: 0.1) }
        return UnitPoint(x: hover.x / 110, y: hover.y / 74)
    }
}

/// Plain button style that reports its pressed state, for the squash animation.
private struct PressReporter: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { isPressed in pressed = isPressed }
    }
}
