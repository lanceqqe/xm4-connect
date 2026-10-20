import SwiftUI
import SonyProtocolKit

/// An array of doubles SwiftUI can interpolate, so the EQ curve morphs between presets.
struct AnimatableValues: VectorArithmetic {
    var values: [Double]

    static var zero: AnimatableValues { AnimatableValues(values: []) }

    private static func combine(_ a: AnimatableValues, _ b: AnimatableValues, _ op: (Double, Double) -> Double) -> AnimatableValues {
        let n = max(a.values.count, b.values.count)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = op(i < a.values.count ? a.values[i] : 0, i < b.values.count ? b.values[i] : 0)
        }
        return AnimatableValues(values: out)
    }

    static func + (a: AnimatableValues, b: AnimatableValues) -> AnimatableValues { combine(a, b, +) }
    static func - (a: AnimatableValues, b: AnimatableValues) -> AnimatableValues { combine(a, b, -) }
    static func += (a: inout AnimatableValues, b: AnimatableValues) { a = a + b }
    static func -= (a: inout AnimatableValues, b: AnimatableValues) { a = a - b }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

/// Maps band values to points inside a rect.
struct EQLayout {
    let rect: CGRect
    let count: Int
    let maximum: Double

    func x(_ index: Int) -> CGFloat {
        guard count > 1 else { return rect.midX }
        return rect.minX + rect.width * CGFloat(index) / CGFloat(count - 1)
    }

    func y(_ value: Double) -> CGFloat {
        rect.midY - CGFloat(value / maximum) * rect.height / 2
    }

    func value(atY y: CGFloat) -> Double {
        Double((rect.midY - y) / (rect.height / 2)) * maximum
    }

    func points(_ values: [Double]) -> [CGPoint] {
        values.enumerated().map { CGPoint(x: x($0.offset), y: y($0.element)) }
    }
}

/// Smooth curve through the band points (Catmull-Rom converted to cubic Béziers).
struct EQCurveShape: Shape {
    var values: AnimatableValues
    var maximum: Double
    var inset: CGSize
    var closed = false

    var animatableData: AnimatableValues {
        get { values }
        set { values = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let layout = EQLayout(rect: rect.insetBy(dx: inset.width, dy: inset.height),
                              count: values.values.count, maximum: maximum)
        let pts = layout.points(values.values)
        var path = Path()
        guard pts.count > 1 else { return path }

        // Extend flat to the edges so the curve fills the whole width.
        let start = CGPoint(x: rect.minX, y: pts[0].y)
        let end = CGPoint(x: rect.maxX, y: pts[pts.count - 1].y)
        let all = [start] + pts + [end]

        path.move(to: all[0])
        for i in 0..<(all.count - 1) {
            let p0 = all[max(i - 1, 0)]
            let p1 = all[i]
            let p2 = all[i + 1]
            let p3 = all[min(i + 2, all.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

struct EqualizerView: View {
    @ObservedObject var model: HeadphonesModel
    var look: ListeningLook

    @State var activeBand: Int?
    @State var hoverBand: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            presetStrip
            if model.hasEqBandData {
                HStack(spacing: 10) {
                    if let bass = model.clearBass { clearBassBar(bass) }
                    curveEditor
                }
                .frame(height: 138)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                placeholder
            }
            footerHint
        }
        .animation(.easeInOut(duration: 0.25), value: model.hasEqBandData)
    }

    // MARK: Presets

    private var presetStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.presets, id: \.rawValue) { preset in
                        presetChip(preset)
                            .id(preset.rawValue)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(model.selectedPreset.rawValue, anchor: .center) }
            .onChange(of: model.selectedPreset) { preset in
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(preset.rawValue, anchor: .center) }
            }
        }
    }

    private func presetChip(_ preset: EqPreset) -> some View {
        let selected = preset == model.selectedPreset
        return Button {
            guard !selected else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                model.selectedPreset = preset
            }
            Haptics.click()
        } label: {
            HStack(spacing: 4) {
                if preset >= .manual {
                    Image(systemName: "slider.vertical.3").font(.system(size: 9, weight: .bold))
                }
                Text(HeadphonesModel.name(of: preset)).font(.rounded(11.5, .semibold))
            }
            .foregroundStyle(selected ? Color.white : Theme.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(selected ? AnyShapeStyle(Theme.gradient(look)) : AnyShapeStyle(Color.white.opacity(0.07)))
                    .shadow(color: selected ? look.accent.1.color.opacity(0.5) : .clear, radius: 6)
            )
        }
        .buttonStyle(.plain)
        .disabled(!model.isConnected || !model.eqAvailable)
    }

    // MARK: Curve

    private var curveEditor: some View {
        GeometryReader { geo in
            let bands = model.frequencyBands
            let maximum = bands.first?.maximum ?? 10
            let inset = CGSize(width: 16, height: 14)
            let plot = CGRect(origin: .zero, size: geo.size).insetBy(dx: inset.width, dy: inset.height)
            let layout = EQLayout(rect: plot, count: bands.count, maximum: maximum)
            let values = AnimatableValues(values: bands.map(\.value))
            let editable = model.eqBandsEditable
            let curveAnimation: Animation? = activeBand == nil ? .spring(response: 0.55, dampingFraction: 0.72) : nil

            ZStack {
                // Grid
                Path { p in
                    for i in 0..<bands.count {
                        p.move(to: CGPoint(x: layout.x(i), y: plot.minY))
                        p.addLine(to: CGPoint(x: layout.x(i), y: plot.maxY))
                    }
                }
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: plot.midY))
                    p.addLine(to: CGPoint(x: geo.size.width, y: plot.midY))
                }
                .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

                // Fill + stroke
                EQCurveShape(values: values, maximum: maximum, inset: inset, closed: true)
                    .fill(LinearGradient(colors: [look.accent.0.color.opacity(0.32), look.accent.1.color.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                EQCurveShape(values: values, maximum: maximum, inset: inset)
                    .stroke(LinearGradient(colors: [look.accent.0.color, look.accent.1.color],
                                           startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                // Knobs and labels
                ForEach(Array(bands.enumerated()), id: \.element.id) { index, band in
                    let point = CGPoint(x: layout.x(index), y: layout.y(band.value))
                    let isActive = activeBand == index
                    let isHover = hoverBand == index
                    Circle()
                        .fill(Color.white)
                        .frame(width: isActive ? 16 : 11, height: isActive ? 16 : 11)
                        .overlay(Circle().strokeBorder(look.accent.1.color, lineWidth: isActive ? 3 : 2))
                        .shadow(color: look.accent.1.color.opacity(isActive || isHover ? 0.9 : 0.4), radius: isActive ? 10 : 5)
                        .position(point)
                        .opacity(editable ? 1 : 0.55)
                    Text(band.label)
                        .font(.rounded(9.5, .medium))
                        .foregroundStyle(isActive ? Theme.textPrimary : Theme.textTertiary)
                        .position(x: point.x, y: geo.size.height - 4)
                    if isActive {
                        Text(band.value > 0 ? "+\(Int(band.value))" : "\(Int(band.value))")
                            .font(.rounded(11, .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(look.accent.0.color))
                            .position(x: point.x, y: max(10, point.y - 22))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .animation(curveAnimation, value: values.values)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard editable, !bands.isEmpty else { return }
                        if activeBand == nil {
                            let nearest = (0..<bands.count).min { a, b in
                                abs(layout.x(a) - drag.startLocation.x) < abs(layout.x(b) - drag.startLocation.x)
                            }
                            withAnimation(.spring(response: 0.2)) { activeBand = nearest }
                        }
                        guard let index = activeBand, index < bands.count else { return }
                        let newValue = layout.value(atY: drag.location.y).rounded()
                        if newValue != bands[index].value,
                           abs(newValue) <= bands[index].maximum {
                            model.setBandValue(newValue, id: bands[index].id)
                            Haptics.tick()
                        }
                    }
                    .onEnded { _ in withAnimation(.spring(response: 0.3)) { activeBand = nil } }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let nearest = (0..<bands.count).min { a, b in
                        abs(layout.x(a) - location.x) < abs(layout.x(b) - location.x)
                    }
                    if hoverBand != nearest { hoverBand = nearest }
                case .ended:
                    hoverBand = nil
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.18))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Vertical Clear Bass slider beside the curve (XM5-class devices).
    private func clearBassBar(_ band: BandModel) -> some View {
        let editable = model.eqBandsEditable
        return VStack(spacing: 6) {
            GeometryReader { geo in
                let h = geo.size.height
                let fraction = (band.value - band.minimum) / (band.maximum - band.minimum)
                let knobY = h - CGFloat(fraction) * h
                ZStack(alignment: .top) {
                    Capsule().fill(Color.white.opacity(0.08))
                    // Fill from the centre line toward the value.
                    let mid = h / 2
                    Capsule()
                        .fill(LinearGradient(colors: [look.accent.1.color, look.accent.0.color],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: max(4, abs(knobY - mid)))
                        .offset(y: min(knobY, mid))
                        .shadow(color: look.accent.0.color.opacity(0.6), radius: 6)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 22, height: 8)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .offset(y: min(max(knobY - 4, 0), h - 8))
                }
                .frame(width: 22)
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: band.value)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        guard editable else { return }
                        let f = 1 - min(max(drag.location.y / h, 0), 1)
                        let v = (band.minimum + Double(f) * (band.maximum - band.minimum)).rounded()
                        if v != band.value {
                            model.setBandValue(v, id: band.id)
                            Haptics.tick()
                        }
                    }
                )
            }
            Text(band.value > 0 ? "+\(Int(band.value))" : "\(Int(band.value))")
                .font(.rounded(11, .bold)).monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text("BASS")
                .font(.rounded(8.5, .heavy))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(width: 44)
        .opacity(editable ? 1 : 0.55)
        .help(Text(verbatim: "Clear Bass"))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(0.18))
            .frame(height: 138)
            .overlay(
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(model.isConnected ? L("Reading the equalizer…", "Lecture de l'égaliseur…")
                                           : L("Equalizer unavailable", "Égaliseur indisponible"))
                        .font(.rounded(11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            )
    }

    @ViewBuilder
    private var footerHint: some View {
        if model.hasEqBandData && !model.eqBandsEditable && model.isConnected {
            Text(L("Pick Manual or Custom to draw your own curve.", "Choisis Manuel ou Perso pour dessiner ta propre courbe."))
                .font(.rounded(10.5))
                .foregroundStyle(Theme.textTertiary)
        } else if model.eqBandsEditable {
            HStack {
                Text(L("Drag the points to shape the sound.", "Glisse les points pour sculpter le son."))
                    .font(.rounded(10.5))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button(L("Reset to flat", "Remettre à plat")) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { model.flattenBands() }
                    Haptics.click()
                }
                .buttonStyle(.plain)
                .font(.rounded(10.5, .semibold))
                .foregroundStyle(look.accent.1.color)
            }
        }
    }
}
