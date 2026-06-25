// Shell-topbar (PoC left-nav herziening). Sterk uitgekleed: de credits-teller,
// de gear (Settings), de board- en de rechter-sidebar-toggle zijn weg — die
// leven nu in de left-nav. De sidebar-inklap-toggle staat op vensterniveau
// (ShellView) náást de traffic-lights, altijd zichtbaar. Wat hier overblijft:
//   • rechts de editor-chrome (Share), die ALLEEN tijdens het bewerken van een
//     portret zichtbaar is — niet op Home of in de Portraits-grid;
//   • een ✕ om de in-window Settings te sluiten.

import AvatarUI
import SwiftUI

struct ShellTopBar: View {
    let isSettingsActive: Bool
    let onToggleSettings: () -> Void
    /// Editor-chrome (Share) toont ALLEEN tijdens het bewerken van een portret.
    var isEditing: Bool = false
    var canExport: Bool = false
    var onExport: () -> Void = {}
    /// E34.5: Preview-knop (social-preview) náást Share, zelfde voorwaarde.
    var canPreview: Bool = false
    var onPreview: () -> Void = {}

    var body: some View {
        toolCluster
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.18), value: isSettingsActive)
    }

    // Rechts: editor-chrome (Share) tijdens bewerken; ✕ in Settings-modus.
    private var toolCluster: some View {
        HStack(spacing: 0) {
            Spacer(minLength: DSSpacing.gap2)
            ZStack(alignment: .trailing) {
                HStack(spacing: DSSpacing.gap2) {
                    if isEditing && canPreview {
                        PreviewButton { onPreview() }
                    }
                    if isEditing && canExport {
                        DSToolButton(Image(systemName: "square.and.arrow.up"), label: "Share", tooltipEdge: .bottom) {
                            onExport()
                        }
                    }
                }
                .opacity(isSettingsActive ? 0 : 1)
                .allowsHitTesting(!isSettingsActive)

                // Enige knop in Settings-modus: ✕ sluit (canonieke sluit-glyph).
                DSToolButton(Image(systemName: "xmark"), label: "Close", tooltipEdge: .bottom) {
                    onToggleSettings()
                }
                .opacity(isSettingsActive ? 1 : 0)
                .allowsHitTesting(isSettingsActive)
            }
            .padding(.trailing, ShellMetrics.topBarInset)
        }
        .padding(.top, DSSpacing.gap3)
        .frame(height: 52, alignment: .top)
    }
}

/// E34.5: gelabelde "Preview"-knop náást Share. Een gevulde pill op dezelfde
/// hoogte als de 48-cirkel-Share-knop, met oog-glyph + tekst (i.p.v. een
/// abstracte icoon-knop). Filled-surface gedrag spiegelt DSToolButton.filled.
private struct PreviewButton: View {
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap1_5) {
                Image(systemName: "eye").font(.system(size: 16, weight: .medium))
                Text("Preview").dsTextStyle(.labelBase)
            }
            .foregroundStyle(DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap4)
            .frame(height: 48)
            .background(
                DSColor.neutralSurface(pressed: pressed, hovering: hovering,
                                       base: DSColor.Background.neutral),
                in: Capsule()
            )
            .scaleEffect(pressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pressEvents(onPress: { pressed = true }, onRelease: { pressed = false })
        .animation(DSMotion.micro, value: hovering)
        .animation(DSMotion.micro, value: pressed)
    }
}

/// Lichtgewicht press-detectie (DragGesture min distance 0) voor de pill-press-
/// state — Button alleen geeft geen pressed-callback in een .plain-style.
private extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}
