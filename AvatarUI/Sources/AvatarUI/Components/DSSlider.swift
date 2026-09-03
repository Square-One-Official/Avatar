// DS-slider (E22.3 / 24.11) — zichtbare thumb + lime actieve track. Vervangt
// SwiftUI's Slider waar de systeem-thumb op lichte surfaces wegvalt.
//
// Visueel dun (4pt track, 16pt thumb) in een 24pt hit-area — een volle
// capsule-track las als een volume-balk, niet als een moderne value-slider.
// `Track.gradient` kleurt de hele baan (temperature/saturation); optionele
// `step` tekent ticks als visuele ankers. Slepen is 1:1 — geen auto-snap.
// (AppKit `allowsTickMarkValuesOnly` default false: ticks verduidelijken,
// ze stelen geen tussenwaarden.) VoiceOver stapt wél per tick.
// Pointer-tracking loopt via AppKit zodat een trackpad-klik tijdens een sleep
// de drag niet afbreekt.

import AppKit
import SwiftUI

/// Horizontale waarde-slider met DS-track (neutral-stronger + lime fill, of
/// een property-gradient) en een zichtbare thumb (witte kern, donkere rand,
/// schaduw — zelfde les als DSColorPicker 24.11).
public struct DSSlider: View {
    public enum Track: Sendable {
        /// Lime (of custom) fill van de leading edge tot de thumb.
        case fill(Color)
        /// Volle-baan gradient; de thumb markeert de stand.
        case gradient([Color])
    }

    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let track: Track
    private let step: Double?
    private let onEditingChanged: (Bool) -> Void

    @State private var isEditing = false
    @Environment(\.dsVectorExport) private var vectorExport

    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        track: Track = .fill(DSColor.Action.primary),
        step: Double? = nil,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.range = range
        self.track = track
        self.step = step
        self.onEditingChanged = onEditingChanged
    }

    /// Klem naar `range`. `step` heeft hier geen effect — ticks zijn visueel.
    public static func snap(
        _ value: Double,
        in range: ClosedRange<Double>,
        step: Double? = nil
    ) -> Double {
        _ = step
        return min(range.upperBound, max(range.lowerBound, value))
    }

    /// Altijd de dichtstbijzijnde tick — voor VoiceOver-stappen, niet voor drag.
    public static func nearestTick(_ value: Double, in range: ClosedRange<Double>, step: Double) -> Double {
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        guard step > 0 else { return clamped }
        let n = ((clamped - range.lowerBound) / step).rounded()
        let snapped = range.lowerBound + n * step
        return min(range.upperBound, max(range.lowerBound, snapped))
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let x = thumbX(for: width)
            ZStack(alignment: .leading) {
                trackView(fillWidth: max(Self.trackHeight, x))
                tickMarks(width: width, height: height)
                thumb
                    .position(x: x, y: height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if vectorExport { EmptyView() } else {
                SliderPointerCatcher(
                    onStart: {
                        if !isEditing {
                            isEditing = true
                            onEditingChanged(true)
                        }
                    },
                    onMove: { locationX, viewWidth in
                        setValue(at: locationX, width: viewWidth)
                    },
                    onEnd: {
                        if isEditing {
                            isEditing = false
                            onEditingChanged(false)
                        }
                    }
                )
                }
            }
        }
        .frame(height: Self.hitHeight)
        .accessibilityElement()
        .accessibilityValue(Text("\(accessibilityPercent) percent"))
        .accessibilityAdjustableAction { direction in
            let increment = step ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment:
                value = step.map { Self.nearestTick(value + increment, in: range, step: $0) }
                    ?? min(range.upperBound, value + increment)
            case .decrement:
                value = step.map { Self.nearestTick(value - increment, in: range, step: $0) }
                    ?? max(range.lowerBound, value - increment)
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private func trackView(fillWidth: CGFloat) -> some View {
        switch track {
        case .fill(let color):
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DSColor.Background.neutralStronger)
                    .frame(height: Self.trackHeight)
                Capsule()
                    .fill(color)
                    .frame(width: fillWidth, height: Self.trackHeight)
            }
        case .gradient(let colors):
            Capsule()
                .fill(
                    LinearGradient(
                        colors: colors.isEmpty ? [DSColor.Background.neutralStronger] : colors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: Self.trackHeight)
        }
    }

    @ViewBuilder
    private func tickMarks(width: CGFloat, height: CGFloat) -> some View {
        let ticks = tickValues
        if !ticks.isEmpty {
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                let isCenter = abs(tick - rangeMid) < (step ?? 1) * 0.25
                let size: CGFloat = isCenter ? 6 : 4
                Circle()
                    .fill(Color.white.opacity(isCenter ? 0.95 : 0.55))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.22), lineWidth: 0.5)
                    )
                    .frame(width: size, height: size)
                    .position(x: x(for: tick, width: width), y: height / 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private var thumb: some View {
        let isGradient: Bool = {
            if case .gradient = track { return true }
            return false
        }()
        return Circle()
            .fill(isGradient ? Color.white.opacity(0.18) : Color.white)
            .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
            .overlay(
                Circle()
                    .strokeBorder(
                        isGradient ? Color.white : DSColor.Foreground.primaryStaticBlack.opacity(0.18),
                        lineWidth: isGradient ? 2.5 : 0.5
                    )
            )
            .dsVectorSafeShadow(color: .black.opacity(isEditing ? 0.28 : 0.16), radius: isEditing ? 2 : 1, y: 1)
            .allowsHitTesting(false)
    }

    /// UXS-13 (UX13): de thumb liep van x=0 tot x=width, dus op beide uiteinden
    /// stak z'n halve breedte búiten het slider-frame — zichtbaar als een
    /// afgekapte thumb tegen de panelrand (het duidelijkst op Temperature, die
    /// als enige een signed range heeft en dus vaak op een extreem staat).
    /// De baan loopt nu van `thumbRadius` tot `width - thumbRadius`.
    private static let trackHeight: CGFloat = 4
    private static let hitHeight: CGFloat = 24
    private static let thumbDiameter: CGFloat = 16
    private static var thumbRadius: CGFloat { thumbDiameter / 2 }

    private var rangeMid: Double {
        (range.lowerBound + range.upperBound) / 2
    }

    private var tickValues: [Double] {
        guard let step, step > 0 else { return [] }
        var values: [Double] = []
        var v = range.lowerBound
        let eps = step * 0.001
        while v <= range.upperBound + eps {
            values.append(min(range.upperBound, max(range.lowerBound, v)))
            v += step
        }
        if let last = values.last, abs(last - range.upperBound) > eps {
            values.append(range.upperBound)
        }
        return values
    }

    private func thumbX(for width: CGFloat) -> CGFloat {
        x(for: value, width: width)
    }

    private func x(for value: Double, width: CGFloat) -> CGFloat {
        let travel = max(0, width - Self.thumbDiameter)
        return Self.thumbRadius + CGFloat(fraction(for: value)) * travel
    }

    private var fraction: Double { fraction(for: value) }

    private func fraction(for value: Double) -> Double {
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
        let raw = range.lowerBound + f * span
        value = min(range.upperBound, max(range.lowerBound, raw))
    }
}

/// AppKit-pointervangnet: `mouseDown` + event-tracking tot `mouseUp`. Extra
/// `leftMouseDown` tijdens de loop (trackpad-klik terwijl je sleept) telt als
/// een positie-update, niet als einde van de drag — SwiftUI's `DragGesture`
/// breekt daarop af en commit't te vroeg.
private struct SliderPointerCatcher: NSViewRepresentable {
    var onStart: () -> Void
    var onMove: (CGFloat, CGFloat) -> Void
    var onEnd: () -> Void

    func makeNSView(context: Context) -> SliderPointerView {
        let view = SliderPointerView()
        view.onStart = onStart
        view.onMove = onMove
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: SliderPointerView, context: Context) {
        view.onStart = onStart
        view.onMove = onMove
        view.onEnd = onEnd
    }
}

private final class SliderPointerView: NSView {
    var onStart: () -> Void = {}
    var onMove: (CGFloat, CGFloat) -> Void = { _, _ in }
    var onEnd: () -> Void = {}
    private var isTracking = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isTracking = true
        onStart()
        send(event)
        // Event-tracking i.p.v. losse mouseDragged: extra leftMouseDown
        // (trackpad-klik tijdens de sleep) blijft een positie-update, SwiftUI's
        // DragGesture zou daarop de drag afbreken. RunLoop.eventTracking
        // pompt tussendoor zodat de live preview kan meelopen.
        while isTracking, window != nil {
            guard let next = window?.nextEvent(
                matching: [.leftMouseUp, .leftMouseDragged, .leftMouseDown],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }
            switch next.type {
            case .leftMouseDragged, .leftMouseDown:
                send(next)
            case .leftMouseUp:
                send(next)
                isTracking = false
                onEnd()
            default:
                break
            }
        }
    }

    private func send(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMove(point.x, bounds.width)
        RunLoop.current.run(mode: .eventTracking, before: Date())
    }
}
