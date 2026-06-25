// Canvas action-toolbar (E24.1–24.4, verslankt in E24.9, popover-stijl E24.12)
// — scène/beeld-acties bovenaan het portret. Top-level items, secundaire
// acties in dropdowns:
//   Frame ▾ (Auto-frame[primair]/Crop/Fix angle/Flip + Shape) · Background.
// E31.2: Adjust → onderste capsule-knop "Enhance". E31.3: AI ▾ (Restore body
// e.a.) is hier weg → de Enhance-paneel-acties (E24.27 + Restore body).
//
// E31.4: deze frame-lokale toolbar bevat nu PUUR frame/scène/compositie-controls
// (Frame-vorm · Background · grid · Flip · Auto-frame/Crop/Fix). FIGMA-TODO:
// hier is GÉÉN Figma-referentie voor (de capsule 4114:978 toont 'm niet — het is
// een team-vondst); dit is een PLACEHOLDER-DESIGN in de geest van het hoofd-
// design (geregistreerd in plan/ASSETS.md #5). Thierry levert het echte design
// later; pas dan 1-op-1 natrekken.
// E24.12: de dropdowns zijn caret-loze, zwevende DS-kaarten (geen systeem-
// `.popover` met pijltje). Eén gedeeld oppervlak (`dsPanelSurface`) — identiek
// aan de bottom-panelen (DSEditPanel). De open-staat leeft als binding zodat
// een klik op de canvas (EditorView) de dropdown sluit, net als de panelen.
//
// E20/E24-iconen: de MENU-iconen (toolbar + dropdowns) zijn Phosphor (hangt aan
// het app-target, niet AvatarUI — zie project.yml). De icon-buttons in de
// bottom-toolbar en de app-bar blijven SF Symbols (besluit Thierry).
//
// E32: deze toolbar deelt nu exact dezelfde DS-componenten als de onderste
// toolbar (`DSCapsuleToolButton` + `.dsToolbarCapsule`), alleen op `.compact`-
// maat. De Phosphor-menu-iconen renderen via de generieke icon-init (Phosphor
// blijft Phosphor); de chevron is een gedeelde SF `chevron.down`. De dropdowns
// delen de paneel-radius (xl4) met de onderste DSEditPanel.

import PhosphorSwift
import AvatarUI
import SwiftUI

/// E24.12: de vier canvas-toolbar-dropdowns (open-staat gedeeld met EditorView).
enum CanvasToolbarMenu: Hashable {
    // E31.2: `adjust` → onderste capsule ("Enhance"). E31.3: `ai` → Enhance-paneel.
    case frame, background
}

struct CanvasActionToolbar<Background: View>: View {
    var onCrop: (() -> Void)?
    var onAutoFrame: () -> Void = {}
    var onFixAngle: (() -> Void)?
    var onFlip: () -> Void = {}
    /// E24.16: huidige frame-vorm + setter (Circle/Square-keuze in Frame ▾).
    var frameShape: ExportShape = .circle
    var onSetFrameShape: (ExportShape) -> Void = { _ in }
    /// E24.12: welke dropdown open is (nil = geen). Binding zodat de
    /// canvas-tap-dismiss in EditorView 'm ook sluit.
    @Binding var activeMenu: CanvasToolbarMenu?
    /// E24.26: grid/thirds-overlay aan/uit (toggle in de toolbar).
    @Binding var gridEnabled: Bool
    /// E31.7: de board hergebruikt deze toolbar maar zonder de editor-only
    /// transform-acties (Auto-frame/Crop/Fix-angle) en zonder de grid-toggle —
    /// die hebben geen effect op een statische board-node. Default true →
    /// single-editor ongewijzigd.
    var showFramingActions: Bool = true
    var showGrid: Bool = true
    @ViewBuilder var background: () -> Background
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DSSpacing.gap1) {
            toolbarItem(.frame, "Frame", icon: .frameCorners, chevron: true, width: 240, padding: DSSpacing.gap2) {
                frameMenu
            }
            toolbarItem(.background, "Background", icon: .image, chevron: false, width: 320, padding: DSSpacing.gap4) {
                background()
            }
            // E24.26: grid/thirds-toggle. E31.7: verborgen op de board (geen
            // alignment-overlay op statische nodes).
            if showGrid {
                // E32: icon-only compact pil — `label: nil`. Active (grid aan) krijgt
                // nu dezelfde lime-ring + lime-tint als een actieve onderste pil.
                DSCapsuleToolButton(
                    isActive: gridEnabled,
                    size: .compact,
                    action: { gridEnabled.toggle() }
                ) {
                    Ph.gridNine.regular
                        .scaledToFit()
                        .frame(width: DSToolbarSize.compact.iconPointSize,
                               height: DSToolbarSize.compact.iconPointSize)
                }
                .help("Toggle alignment grid")
            }
        }
        // E32: zelfde solide Card-capsule als de onderste toolbar (geen glas/rand),
        // alleen compacter (`.compact`).
        .dsToolbarCapsule(size: .compact)
        .dsMotion(DSMotion.fast, value: activeMenu)
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--show-bg-popover") { activeMenu = .background }
            if args.contains("--show-frame-popover") { activeMenu = .frame }
        }
        #endif
    }

    /// E24.12: een toolbar-knop met zijn caret-loze, zwevende dropdown-kaart
    /// eronder (overlay, niet door de capsule geclipt). De kaart deelt het
    /// `dsPanelSurface`-oppervlak met de bottom-panelen.
    @ViewBuilder
    private func toolbarItem<Content: View>(
        _ menu: CanvasToolbarMenu, _ title: String, icon: Ph,
        chevron: Bool, width: CGFloat, padding: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        // E32: gedeelde compact-pil i.p.v. de inline `menuButton`. De Phosphor-
        // menu-iconen blijven Phosphor (generieke icon-init); de chevron is een
        // gedeelde SF `chevron.down`. Active (menu open) krijgt nu de lime-ring.
        DSCapsuleToolButton(
            label: title,
            showChevron: chevron,
            isActive: activeMenu == menu,
            size: .compact,
            action: { activeMenu = (activeMenu == menu) ? nil : menu }
        ) {
            icon.regular
                .scaledToFit()
                .frame(width: DSToolbarSize.compact.iconPointSize,
                       height: DSToolbarSize.compact.iconPointSize)
        }
        .overlay(alignment: .top) {
            if activeMenu == menu {
                content()
                    .padding(padding)
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                    // E32: zelfde paneel-radius (xl4 = 24) als de onderste DSEditPanel.
                    .dsPanelSurface(cornerRadius: DSRadius.xl4)
                    // Onder de capsule: pil-hoogte + capsule-inset + lucht (= 44).
                    .offset(y: DSToolbarSize.compact.height
                              + DSToolbarSize.compact.containerPadding
                              + DSSpacing.gap2)
                    .zIndex(10)
                    .transition(.dsScaleFade(anchor: .top, reduceMotion: reduceMotion))
            }
        }
    }

    // MARK: Dropdown-inhoud

    private var frameMenu: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            // E31.7: de transform-acties bestaan alleen in de single-editor
            // (live transform-state); op de board tonen we enkel Flip + Shape.
            if showFramingActions {
                menuRow("Auto-frame & center", icon: .cornersOut, action: onAutoFrame)
                menuRow("Crop", icon: .crop, action: onCrop)
                menuRow("Fix camera angle", icon: .perspective, action: onFixAngle)
            }
            menuRow("Flip horizontal", icon: .flipHorizontal, action: onFlip)

            // E24.16: frame-vorm-keuze. Cirkel = merkvorm (default), vierkant
            // als alternatief; de actieve vorm krijgt een checkmark.
            Divider().padding(.vertical, DSSpacing.gap1)
            Text("Shape")
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.muted)
                .padding(.horizontal, DSSpacing.gap3)
                .padding(.bottom, DSSpacing.gap1)
            shapeRow("Circle", icon: .circle, shape: .circle)
            shapeRow("Square", icon: .square, shape: .square)
        }
    }

    private func shapeRow(_ title: String, icon: Ph, shape: ExportShape) -> some View {
        Button {
            activeMenu = nil
            onSetFrameShape(shape)
        } label: {
            HStack(spacing: DSSpacing.gap2) {
                icon.regular.scaledToFit().frame(width: 16, height: 16)
                Text(title).dsTextStyle(.labelBase).foregroundStyle(DSColor.Foreground.primary)
                Spacer(minLength: DSSpacing.gap2)
                if frameShape == shape {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DSColor.Action.primaryForeground)
                }
            }
            .foregroundStyle(DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap3)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dsHoverHighlight(cornerRadius: DSRadius.md)
        }
        .buttonStyle(.plain)
    }

    /// Een dropdown-rij; `action == nil` = nog-niet-gebouwde stub (gedimd).
    private func menuRow(_ title: String, icon: Ph, pro: Bool = false, action: (() -> Void)?) -> some View {
        Button {
            activeMenu = nil
            action?()
        } label: {
            HStack(spacing: DSSpacing.gap2) {
                icon.regular.scaledToFit().frame(width: 16, height: 16)
                Text(title).dsTextStyle(.labelBase).foregroundStyle(DSColor.Foreground.primary)
                Spacer(minLength: DSSpacing.gap2)
                if pro { DSProChip() }
            }
            .foregroundStyle(DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap3)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dsHoverHighlight(cornerRadius: DSRadius.md)
        }
        .buttonStyle(.plain)
        .opacity(action == nil ? 0.45 : 1)
        .disabled(action == nil)
    }

}
