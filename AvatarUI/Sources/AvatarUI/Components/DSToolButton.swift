// 48-cirkel-toolknop (Figma Stories → Bottom toolbar).
// Surface-varianten:
// - .filled (default, window-top-bar): vlakke cirkel DSColor.Background.neutral
//   (rgba wit@5%) in rust → hover neutralStronger, pressed neutralStrongest.
// - .ghost (onderste editor-toolbar, besluit Thierry 2026-06-22): transparant in
//   rust → fill verschijnt pas op hover/active/pressed (gelijk aan de pillen).
// Beide: scale(0.94) op pressed, active = lime ring b-medium + lime icoon.

import SwiftUI

public struct DSToolButton: View {
    public enum Surface: Sendable {
        case filled
        case ghost
    }

    private let icon: Image
    private let label: String
    private let isActive: Bool
    private let surface: Surface
    private let action: () -> Void

    /// E18.10: aan welke kant de tooltip verschijnt. Top-bar-knoppen (gear/
    /// share) staan tegen de vensterrand → tooltip eronder; toolbar/editor-
    /// knoppen onderin → tooltip erboven.
    private let tooltipEdge: VerticalEdge
    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var tooltipHeight: CGFloat = 0

    public init(
        _ icon: Image,
        label: String,
        isActive: Bool = false,
        surface: Surface = .filled,
        tooltipEdge: VerticalEdge = .top,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.isActive = isActive
        self.surface = surface
        self.tooltipEdge = tooltipEdge
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // E… active-state: kruisvervaag twee vaste-kleur iconen op opacity
            // i.p.v. een foregroundStyle-kleurtween. Een kleurtween loopt door
            // vuile tussentinten en wordt door een ouder-spring (sidebar-slide)
            // hortend; een opacity-crossfade van twee schone kleuren blijft
            // crisp onder elke overgenomen curve. De ring is al opacity-based.
            ZStack {
                styledIcon(DSColor.Foreground.primary)
                    .opacity(isActive ? 0 : 1)
                styledIcon(DSColor.Action.primaryForeground)
                    .opacity(isActive ? 1 : 0)
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(ToolSurfaceStyle(isActive: isActive, surface: surface))
        .accessibilityLabel(Text(label))
        // Tooltip-hover los van de surface-hover: aparte @State voor de delay-logica.
        .onHover { isHovering = $0 }
        .task(id: isHovering) {
            guard isHovering else { showTooltip = false; return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            showTooltip = true
        }
        // E18.10v4: tooltip gecentreerd boven/onder de 48-knop.
        .overlay(alignment: tooltipEdge == .top ? .top : .bottom) {
            if showTooltip {
                DSTooltip(label, caretEdge: tooltipEdge == .top ? .bottom : .top)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: DSToolButtonTipHeightKey.self, value: proxy.size.height
                            )
                        }
                    )
                    .offset(y: tooltipEdge == .top
                        ? -(tooltipHeight + DSSpacing.gap1)
                        : (tooltipHeight + DSSpacing.gap1))
                    .onPreferenceChange(DSToolButtonTipHeightKey.self) { tooltipHeight = $0 }
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .dsMotion(DSMotion.micro, value: showTooltip)
    }

    private func styledIcon(_ color: Color) -> some View {
        icon
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(color)
    }
}

private struct ToolSurfaceStyle: ButtonStyle {
    let isActive: Bool
    let surface: DSToolButton.Surface

    func makeBody(configuration: Configuration) -> some View {
        ToolSurface(isActive: isActive, surface: surface, configuration: configuration)
    }
}

private struct ToolSurface: View {
    let isActive: Bool
    let surface: DSToolButton.Surface
    let configuration: ButtonStyle.Configuration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .background(backgroundColor, in: Circle())
            // E03.15: ring altijd aanwezig, geschakeld via opacity zodat hij
            // mee-animeert bij canvas-verschuivingen zonder layout-herberekening.
            .overlay {
                Circle()
                    .strokeBorder(
                        DSColor.Action.primaryForeground,
                        lineWidth: DSBorderWidth.medium
                    )
                    .opacity(isActive ? DSOpacity.strong : DSOpacity.hidden)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .onHover { isHovering = $0 }
            // Active-state (ring + icoon-crossfade) MOET zijn eigen schone curve
            // rijden, ook als de knop tegelijk meeschuift met de sidebar. Een
            // gewone `.animation(value: isActive)` verliest het van de ouder-
            // `.animation(.spring, value: isSidebarVisible)` wanneer beide states
            // in dezelfde transactie wijzigen → de ring/tint kreeg de spring
            // (overshoot/wobble) i.p.v. de bedoelde easeOut. Een `.transaction`
            // override op dezelfde trigger is lokaal en wint wél van de ouder.
            .transaction(value: isActive) { txn in
                txn.animation = DSMotion.fast
            }
            .dsMotion(DSMotion.micro, value: isHovering)
            .dsMotion(DSMotion.micro, value: configuration.isPressed)
    }

    private var backgroundColor: Color {
        switch surface {
        case .filled:
            return DSColor.neutralSurface(
                pressed: configuration.isPressed, hovering: isHovering,
                base: DSColor.Background.neutral
            )
        case .ghost:
            return DSColor.neutralSurface(
                pressed: isActive || configuration.isPressed, hovering: isHovering
            )
        }
    }
}

/// E18.10v4: meet de tooltip-hoogte zodat hij precies boven/onder de knop valt.
private struct DSToolButtonTipHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// In-window-blur voor glas-panelen (DSPanelSurface, e.a.) — SwiftUI's
/// .ultraThinMaterial blendt op macOS achter het venster en oogt vlak op
/// een donker vlak; withinWindow blendt de content eronder.
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
