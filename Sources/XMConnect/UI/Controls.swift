import AppKit
import SwiftUI

enum Haptics {
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func click() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Frosted card used to group controls.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.cardStroke, lineWidth: 1)
                    )
            )
    }
}

/// A switch whose track fills with the mode gradient and whose knob springs across.
struct GlowToggleStyle: ToggleStyle {
    var look: ListeningLook

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                configuration.isOn.toggle()
            }
            Haptics.click()
        } label: {
            HStack(spacing: 10) {
                configuration.label
                Spacer(minLength: 8)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn
                              ? AnyShapeStyle(Theme.gradient(look))
                              : AnyShapeStyle(Color.white.opacity(0.12)))
                        .frame(width: 40, height: 23)
                        .shadow(color: configuration.isOn ? look.accent.1.color.opacity(0.55) : .clear,
                                radius: 8)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 19, height: 19)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .padding(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One labelled option row: icon, title, optional detail, then the control.
struct OptionLabel: View {
    let icon: String
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.rounded(13, .medium))
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.rounded(10.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Horizontal slider with a glowing gradient fill, integer steps and a haptic tick per step.
struct GlowSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var look: ListeningLook
    var enabled = true

    @State var dragging = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let knobX = 11 + CGFloat(fraction) * (width - 22)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 8)
                Capsule()
                    .fill(Theme.gradient(look))
                    .frame(width: max(8, knobX + 4), height: 8)
                    .shadow(color: look.accent.1.color.opacity(enabled ? 0.6 : 0), radius: 8)
                // Step marks
                HStack(spacing: 0) {
                    ForEach(0..<5) { i in
                        Circle().fill(Color.white.opacity(0.25)).frame(width: 2.5, height: 2.5)
                        if i < 4 { Spacer() }
                    }
                }
                .padding(.horizontal, 12)
                Circle()
                    .fill(Color.white)
                    .frame(width: dragging ? 24 : 20, height: dragging ? 24 : 20)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    .overlay(Circle().fill(look.accent.1.color).frame(width: 6, height: 6))
                    .position(x: knobX, y: geo.size.height / 2)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard enabled else { return }
                        dragging = true
                        let f = min(max((drag.location.x - 11) / max(1, width - 22), 0), 1)
                        let newValue = (range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)).rounded()
                        if newValue != value {
                            value = newValue
                            Haptics.tick()
                        }
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: 28)
        .opacity(enabled ? 1 : 0.4)
        .animation(.easeOut(duration: 0.2), value: enabled)
    }
}

/// Circular battery gauge with an animated gradient arc.
struct BatteryRing: View {
    let level: Int?
    let charging: Bool
    var look: ListeningLook

    var body: some View {
        let fraction = Double(level ?? 0) / 100
        let low = (level ?? 100) <= 20
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    low ? AnyShapeStyle(Color(red: 1, green: 0.35, blue: 0.35))
                        : AnyShapeStyle(AngularGradient(colors: [look.accent.0.color, look.accent.1.color, look.accent.0.color],
                                                        center: .center)),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.9, dampingFraction: 0.8), value: fraction)
            VStack(spacing: -1) {
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.yellow)
                }
                Text(level.map { "\($0)" } ?? "–")
                    .font(.rounded(11.5, .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
        }
        .frame(width: 38, height: 38)
        .help(level.map { L("Battery: \($0) %", "Batterie : \($0) %") } ?? L("Battery unknown", "Batterie inconnue"))
    }
}

/// Pill-shaped button used in the footer.
struct PillButton: View {
    let icon: String
    let title: String
    var tint: Color = Theme.textSecondary
    var filled: Color? = nil
    let action: () -> Void

    @State var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.rounded(12, .semibold))
            }
            .foregroundStyle(filled == nil ? tint : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(filled ?? Color.white.opacity(hovering ? 0.12 : 0.06))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
            .scaleEffect(hovering ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }
}
