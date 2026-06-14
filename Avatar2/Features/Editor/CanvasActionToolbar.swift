// Canvas action-toolbar (E24.1–24.4, verslankt in E24.9, popover-stijl E24.12)
// — scène/beeld-acties bovenaan het portret. Vier top-level items, secundaire
// acties in dropdowns:
//   Frame ▾ (Auto-frame[primair]/Crop/Fix angle/Flip + Shape) · Background ·
//   Adjust · AI ▾ (Improve lighting/Colorise/Boost/Restore body).
// E24.12: de dropdowns zijn caret-loze, zwevende DS-kaarten (geen systeem-
// `.popover` met pijltje). Eén gedeeld oppervlak (`dsPanelSurface`) — identiek
// aan de bottom-panelen (DSEditPanel). De open-staat leeft als binding zodat
// een klik op de canvas (EditorView) de dropdown sluit, net als de panelen.
//
// E20/E24-iconen: de MENU-iconen (toolbar + dropdowns) zijn Phosphor (hangt aan
// het app-target, niet AvatarUI — zie project.yml). De icon-buttons in de
// bottom-toolbar en de app-bar blijven SF Symbols (besluit Thierry).

import PhosphorSwift
import AvatarUI
import SwiftUI

/// E24.12: de vier canvas-toolbar-dropdowns (open-staat gedeeld met EditorView).
enum CanvasToolbarMenu: Hashable {
    case frame, background, adjust, ai
}

struct CanvasActionToolbar<Adjust: View, Background: View>: View {
    var onCrop: (() -> Void)?
    var onAutoFrame: () -> Void = {}
    var onFixAngle: (() -> Void)?
    var onFlip: () -> Void = {}
    /// E24.16: huidige frame-vorm + setter (Circle/Square-keuze in Frame ▾).
    var frameShape: ExportShape = .circle
    var onSetFrameShape: (ExportShape) -> Void = { _ in }
    var onRestoreBody: () -> Void = {}
    var onImproveLighting: () -> Void = {}
    var onColorise: () -> Void = {}
    var onBoost: () -> Void = {}
    var isPro: Bool = false
    /// E24.12: welke dropdown open is (nil = geen). Binding zodat de
    /// canvas-tap-dismiss in EditorView 'm ook sluit.
    @Binding var activeMenu: CanvasToolbarMenu?
    /// E24.26: grid/thirds-overlay aan/uit (toggle in de toolbar).
    @Binding var gridEnabled: Bool
    @ViewBuilder var adjust: () -> Adjust
    @ViewBuilder var background: () -> Background

    var body: some View {
        HStack(spacing: DSSpacing.gap1) {
            toolbarItem(.frame, "Frame", icon: .frameCorners, chevron: true, width: 240, padding: DSSpacing.gap2) {
                frameMenu
            }
            toolbarItem(.background, "Background", icon: .image, chevron: false, width: 320, padding: DSSpacing.gap4) {
                background()
            }
            toolbarItem(.adjust, "Adjust", icon: .slidersHorizontal, chevron: false, width: 360, padding: DSSpacing.gap5) {
                adjust()
            }
            toolbarItem(.ai, "AI", icon: .sparkle, chevron: true, width: 240, padding: DSSpacing.gap2) {
                aiMenu
            }

            // E24.26: grid/thirds-toggle.
            Button { gridEnabled.toggle() } label: {
                Ph.gridNine.regular
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .padding(.horizontal, DSSpacing.gap2)
                    .frame(height: 32)
                    .background(gridEnabled ? DSColor.Background.neutralStronger : .clear, in: Capsule())
                    .dsHoverHighlight(cornerRadius: 16)
            }
            .buttonStyle(.plain)
            .help("Toggle alignment grid")
        }
        .padding(DSSpacing.gap1)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
        .animation(.easeOut(duration: 0.14), value: activeMenu)
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--show-bg-popover") { activeMenu = .background }
            if args.contains("--show-ai-popover") { activeMenu = .ai }
            if args.contains("--show-frame-popover") { activeMenu = .frame }
            if args.contains("--show-adjust-popover") { activeMenu = .adjust }
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
        menuButton(title, icon: icon, isActive: activeMenu == menu, chevron: chevron) {
            activeMenu = (activeMenu == menu) ? nil : menu
        }
        .overlay(alignment: .top) {
            if activeMenu == menu {
                content()
                    .padding(padding)
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                    .dsPanelSurface(cornerRadius: DSRadius.xl)
                    // Onder de capsule (knop 32 + capsule-padding + lucht).
                    .offset(y: 44)
                    .zIndex(10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
    }

    // MARK: Dropdown-inhoud

    private var frameMenu: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            menuRow("Auto-frame & center", icon: .cornersOut, action: onAutoFrame)
            menuRow("Crop", icon: .crop, action: onCrop)
            menuRow("Fix camera angle", icon: .perspective, action: onFixAngle)
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
                        .foregroundStyle(DSColor.Action.primary)
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

    private var aiMenu: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            menuRow("Improve lighting", icon: .sun, action: onImproveLighting)
            menuRow("Colorise", icon: .palette, pro: !isPro, action: onColorise)
            menuRow("Boost resolution", icon: .arrowsOut, pro: !isPro, action: onBoost)
            menuRow("Restore body", icon: .userRectangle, pro: !isPro, action: onRestoreBody)
        }
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

    private func menuButton(_ title: String, icon: Ph, isActive: Bool, chevron: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap1) {
                icon.regular.scaledToFit().frame(width: 15, height: 15)
                Text(title).dsTextStyle(.labelSmall)
                if chevron { Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
            }
            .foregroundStyle(DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 32)
            .background(isActive ? DSColor.Background.neutralStronger : .clear, in: Capsule())
            .dsHoverHighlight(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}
