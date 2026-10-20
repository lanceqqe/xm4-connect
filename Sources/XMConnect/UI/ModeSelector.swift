import SwiftUI
import SonyProtocolKit

/// Tiles: Noise cancelling / Wind / Ambient / Off. The selected tile carries the mode gradient,
/// which slides between tiles.
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

    @State var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(height: 22)
                Text(title)
                    .font(.rounded(11.5, .semibold))
            }
            .foregroundStyle(selected ? Color.white : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.09 : 0.05))
                    if selected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.gradient(look))
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
