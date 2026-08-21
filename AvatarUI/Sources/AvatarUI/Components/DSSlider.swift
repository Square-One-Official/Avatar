// DS-slider (E22.3 / 24.11) — zichtbare thumb + lime actieve track. Vervangt
// SwiftUI's Slider waar de systeem-thumb op lichte surfaces wegvalt.
//
// Visueel dun (3pt track, 12pt thumb) in een 24pt hit-area — de oude 20pt
// capsule-track las als een volume-balk, niet als een moderne value-slider.

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
                    .frame(height: Self.trackHeight)
                Capsule()
                    .fill(DSColor.Action.primary)
                    .frame(width: max(Self.trackHeight, x), height: Self.trackHeight)
                thumb
                    .position(x: x, y: height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(height: Self.hitHeight)
        .accessibilityElement()
        .accessibilityValue(Text("\(accessibilityPercent) percent"))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment:
                value = min(range.upperBound, value + step)
            case .decrement:
                value = max(range.lowerBound, value - step)
            @unknown default:
                break
            }
        }
    }

    private var thumb: some View {
        Circle()
            .fill(Color.white)
            .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
            .overlay(
                Circle()
                    .strokeBorder(DSColor.Foreground.primaryStaticBlack.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(isEditing ? 0.28 : 0.16), radius: isEditing ? 2 : 1, y: 1)
            .allowsHitTesting(false)
    }

    /// UXS-13 (UX13): de thumb liep van x=0 tot x=width, dus op beide uiteinden
    /// stak z'n halve breedte búiten het slider-frame — zichtbaar als een
    /// afgekapte thumb tegen de panelrand (het duidelijkst op Temperature, die
    /// als enige een signed range heeft en dus vaak op een extreem staat).
    /// De baan loopt nu van `thumbRadius` tot `width - thumbRadius`.
    private static let trackHeight: CGFloat = 3
    private static let hitHeight: CGFloat = 24
    private static let thumbDiameter: CGFloat = 12
    private static var thumbRadius: CGFloat { thumbDiameter / 2 }

    private func thumbX(for width: CGFloat) -> CGFloat {
        let travel = max(0, width - Self.thumbDiameter)
        return Self.thumbRadius + CGFloat(fraction) * travel
    }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return ((value - range.lowerBound) / span).clamped01
    }

    private var accessibilityPercent: Int {
        Int((fraction * 100).rounded())
    }

    private func setValue(at x: CGFloat, width: CGFloat) {
        let span = range.upperBound - range.lowerBound
        // Spiegelt `thumbX`: klikken op de uiterste rand hoort min/max te geven,
        // niet een waarde die net binnen de baan valt.
        let travel = max(1, width - Self.thumbDiameter)
        let f = (Double(x - Self.thumbRadius) / Double(travel)).clamped01
        value = range.lowerBound + f * span
    }
}
