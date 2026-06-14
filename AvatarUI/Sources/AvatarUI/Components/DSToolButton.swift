// 48-cirkel-toolknop (E03.11; Figma Components → Icon-Only Button en de
// toolbar/gear in App / Edit). De cirkels zijn in het design geen vlakke
// fill maar een glazige donkere material met subtiele rand/highlight —
// Figma exposeert dat effect niet als variabele, dus: ultraThinMaterial
// + background/neutral + dunne rim die van boven licht oploopt (geijkt op
// de frames). Active = lime ring b-medium + lime icoon (E03.3-gedrag).

import SwiftUI

public struct DSToolButton: View {
    private let icon: Image
    private let label: String
    private let isActive: Bool
    private let action: () -> Void

    /// E18.10: aan welke kant de tooltip verschijnt. Top-bar-knoppen (gear/
    /// share) staan tegen de vensterrand → tooltip eronder; toolbar/editor-
    /// knoppen onderin → tooltip erboven.
    private let tooltipEdge: VerticalEdge
    @State private var isHovering = false
    @State private var showTooltip = false

    public init(
        _ icon: Image,
        label: String,
        isActive: Bool = false,
        tooltipEdge: VerticalEdge = .top,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.isActive = isActive
        self.tooltipEdge = tooltipEdge
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            icon
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? DSColor.Action.primary : DSColor.Foreground.primary)
                .frame(width: 48, height: 48)
                .background { DSGlassCircle() }
                // Ring altijd onderdeel van de button-view en alleen via
                // opacity geschakeld (E03.15, bevinding 16): een
                // conditionele insert hertekent buiten de lopende
                // layout-animatie om en doet de ring verspringen bij de
                // canvas-verschuiving; zo animeert hij gewoon mee.
                .overlay {
                    Circle()
                        .strokeBorder(
                            DSColor.Action.primary,
                            lineWidth: DSBorderWidth.medium
                        )
                        .opacity(isActive ? DSOpacity.strong : DSOpacity.hidden)
                }
                .animation(.easeOut(duration: 0.15), value: isActive)
        }
        .buttonStyle(DSStateOpacityButtonStyle())
        .accessibilityLabel(Text(label))
        // E18.10: eigen tooltip (Figma Tooltip-component) i.p.v. native .help
        // (die plaatste 'm willekeurig en oogde te subtiel). Gecentreerd bóven
        // (of, voor topbar-knoppen tegen de rand, ónder) het icoon, met de
        // caret 4px van de knop, na ~1,2s hover.
        .onHover { isHovering = $0 }
        .task(id: isHovering) {
            guard isHovering else { showTooltip = false; return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            showTooltip = true
        }
        .overlay(alignment: tooltipEdge == .top ? .top : .bottom) {
            if showTooltip {
                DSTooltip(label, caretEdge: tooltipEdge == .top ? .bottom : .top)
                    .alignmentGuide(tooltipEdge == .top ? .top : .bottom) { dims in
                        // Caret 4px (min.) van de knop; gecentreerd via .top/.bottom.
                        tooltipEdge == .top
                            ? dims[.bottom] + DSSpacing.gap1
                            : dims[.top] - DSSpacing.gap1
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.12), value: showTooltip)
    }
}

/// De glass-surface van de toolcirkels (E03.14, bevinding 10) — in lagen
/// zoals Figma: (a) NSVisualEffectView met withinWindow-blending zodat
/// onderliggende content (de foto) met blur doorschemert — SwiftUI's
/// Material bleek op zwart vlak te renderen; (b) neutral-tint; (c)
/// gradient-rim: licht bovenaan, donker onderaan; (d) inner-highlight
/// bovenin de cirkel.
struct DSGlassCircle: View {
    var body: some View {
        ZStack {
            WithinWindowBlur()
                .clipShape(Circle())
            Circle().fill(DSColor.Background.neutral)
            Circle().fill(
                LinearGradient(
                    colors: [DSColor.Foreground.primary.opacity(0.10), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            Circle().strokeBorder(
                LinearGradient(
                    colors: [
                        DSColor.Foreground.primary.opacity(0.25),
                        Color.black.opacity(0.35)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: DSBorderWidth.thin
            )
        }
    }
}

/// In-window-blur: NSVisualEffectView die de content erónder in hetzelfde
/// venster vervaagt (SwiftUI's .ultraThinMaterial blendt op macOS achter
/// het venster en oogt vlak op een zwart vlak). E18.22: ook gebruikt voor de
/// glas-panelen, instelbaar materiaal.
struct WithinWindowBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
