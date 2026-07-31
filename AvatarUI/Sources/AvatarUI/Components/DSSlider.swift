// DS-slider (E22.3 / 24.11) — zichtbare thumb + lime actieve track. Vervangt
// SwiftUI's Slider waar de systeem-thumb op lichte surfaces wegvalt.

import SwiftUI

/// Horizontale waarde-slider met DS-track (neutral-stronger + lime fill) en een
/// zichtbare thumb (witte kern, donkere rand, schaduw — zelfde les als
/// DSColorPicker 24.11).
public struct DSSlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let onEditingChanged: (Bool) -> Void

    @State private var isEditing = false

    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.range = range
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let x = thumbX(for: width)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DSColor.Background.neutralStronger)
                Capsule()
                    .fill(DSColor.Action.primary)
                    .frame(width: max(0, x))
                thumb
                    .position(x: x, y: height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isEditing {
                            isEditing = true
                            onEditingChanged(true)
                        }
                        setValue(at: drag.location.x, width: width)
                    }
                    .onEnded { _ in
                        if isEditing {
                            isEditing = false
                            onEditingChanged(false)
                        }
                    }
            )
        }
        .frame(height: 20)
    }

    private var thumb: some View {
        Circle()
            .fill(.white)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .overlay(Circle().strokeBorder(DSColor.Foreground.primaryStaticBlack.opacity(0.28), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .allowsHitTesting(false)
    }

    private func thumbX(for width: CGFloat) -> CGFloat {
        CGFloat(fraction) * width
    }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return ((value - range.lowerBound) / span).clamped01
    }

    private func setValue(at x: CGFloat, width: CGFloat) {
        let span = range.upperBound - range.lowerBound
        let f = (Double(x) / Double(max(1, width))).clamped01
        value = range.lowerBound + f * span
    }
}
