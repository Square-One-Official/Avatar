// Canvas action-toolbar (E24.1–24.4, verslankt in E24.9) — scène/beeld-acties
// bovenaan het portret. Vier top-level items, secundaire acties in dropdowns:
//   Frame ▾ (Auto-frame[primair]/Crop/Fix angle/Flip) · Background · Adjust ·
//   AI ▾ (Improve lighting/Colorise/Boost/Restore body).
// Alle dropdowns zijn dezelfde DS-popover (geen native menu); rijen hebben
// hover-highlight. De toolbar staat alleen op de canvas als er een portret is
// (result-state) — slank en altijd zichtbaar, niet hover-only.

import AvatarUI
import SwiftUI

struct CanvasActionToolbar<Adjust: View, Background: View>: View {
    var onCrop: (() -> Void)?
    var onAutoFrame: () -> Void = {}
    var onFixAngle: (() -> Void)?
    var onFlip: () -> Void = {}
    var onRestoreBody: () -> Void = {}
    var onImproveLighting: () -> Void = {}
    var onColorise: () -> Void = {}
    var onBoost: () -> Void = {}
    var isPro: Bool = false
    @ViewBuilder var adjust: () -> Adjust
    @ViewBuilder var background: () -> Background

    @State private var showFrame = false
    @State private var showAdjust = false
    @State private var showBackground = false
    @State private var showAI = false

    var body: some View {
        HStack(spacing: DSSpacing.gap1) {
            // Frame ▾
            menuButton("Frame", systemImage: "crop", isActive: showFrame) { showFrame = true }
                .popover(isPresented: $showFrame, arrowEdge: .bottom) {
                    frameMenu.padding(DSSpacing.gap2).frame(width: 240)
                }

            // Background (popover)
            menuButton("Background", systemImage: "photo", isActive: showBackground, chevron: false) { showBackground = true }
                .popover(isPresented: $showBackground, arrowEdge: .bottom) {
                    background().padding(DSSpacing.gap4).frame(width: 320)
                }

            // Adjust (color-sliders popover)
            menuButton("Adjust", systemImage: "slider.horizontal.3", isActive: showAdjust, chevron: false) { showAdjust = true }
                .popover(isPresented: $showAdjust, arrowEdge: .bottom) {
                    adjust().padding(DSSpacing.gap5).frame(width: 360)
                }

            // AI ▾
            menuButton("AI", systemImage: "sparkles", isActive: showAI, chevron: true) { showAI = true }
                .popover(isPresented: $showAI, arrowEdge: .bottom) {
                    aiMenu.padding(DSSpacing.gap2).frame(width: 240)
                }
        }
        .padding(DSSpacing.gap1)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--show-bg-popover") { showBackground = true }
            if args.contains("--show-ai-popover") { showAI = true }
            if args.contains("--show-frame-popover") { showFrame = true }
        }
        #endif
    }

    // MARK: Dropdown-inhoud

    private var frameMenu: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            menuRow("Auto-frame & center", systemImage: "viewfinder", action: onAutoFrame)
            menuRow("Crop", systemImage: "crop", action: onCrop)
            menuRow("Fix camera angle", systemImage: "camera", action: onFixAngle)
            menuRow("Flip horizontal", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", action: onFlip)
        }
    }

    private var aiMenu: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            menuRow("Improve lighting", systemImage: "wand.and.stars", action: onImproveLighting)
            menuRow("Colorise", systemImage: "paintpalette", pro: !isPro, action: onColorise)
            menuRow("Boost resolution", systemImage: "arrow.up.left.and.arrow.down.right", pro: !isPro, action: onBoost)
            menuRow("Restore body", systemImage: "person.crop.rectangle", pro: !isPro, action: onRestoreBody)
        }
    }

    /// Een dropdown-rij; `action == nil` = nog-niet-gebouwde stub (gedimd).
    private func menuRow(_ title: String, systemImage: String, pro: Bool = false, action: (() -> Void)?) -> some View {
        Button {
            showFrame = false; showAI = false
            action?()
        } label: {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: systemImage).font(.system(size: 13, weight: .medium)).frame(width: 18)
                Text(title).dsTextStyle(.labelBase).foregroundStyle(DSColor.Foreground.primary)
                Spacer(minLength: DSSpacing.gap2)
                if pro { DSProChip() }
            }
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

    private func menuButton(_ title: String, systemImage: String, isActive: Bool, chevron: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap1) {
                Image(systemName: systemImage).font(.system(size: 13, weight: .medium))
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
