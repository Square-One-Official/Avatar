// Canvas action-toolbar (E24.1–24.4) — scène/beeld-acties als tekst+icoon-
// knoppen, vastgemaakt bóven het portret. Vervangt de losse rechter-cluster
// (E22.2). Bevat: frame-acties (Crop/Auto-frame/Fix angle/Flip/Restore body),
// Background (popover), Adjust (popover met color-sliders, 24.3) en AI
// (zichtbare dropdown: Colorise/Boost, 24.2). De persoon-tools (Effects/Face/
// Clothing/Hair) blijven in de bottom-toolbar.

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

    @State private var showAdjust = false
    @State private var showBackground = false
    @State private var showAI = false

    var body: some View {
        HStack(spacing: DSSpacing.gap1) {
            item("Crop", systemImage: "crop", action: onCrop)
            item("Auto-frame", systemImage: "viewfinder") { onAutoFrame() }
            item("Fix angle", systemImage: "camera", action: onFixAngle)
            item("Flip", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { onFlip() }
            item("Restore body", systemImage: "arrow.up.left.and.arrow.down.right") { onRestoreBody() }

            divider

            button("Background", systemImage: "photo", isActive: showBackground) { showBackground = true }
                .popover(isPresented: $showBackground, arrowEdge: .bottom) {
                    background().padding(DSSpacing.gap4).frame(width: 320)
                }
            button("Adjust", systemImage: "slider.horizontal.3", isActive: showAdjust) { showAdjust = true }
                .popover(isPresented: $showAdjust, arrowEdge: .bottom) {
                    adjust().padding(DSSpacing.gap5).frame(width: 360)
                }

            // E24.2-fix: AI-edits via dezelfde DS-popover als Background/Adjust
            // (geen native menu).
            Button { showAI = true } label: {
                label("AI", systemImage: "sparkles", isActive: showAI, chevron: true)
            }
            .buttonStyle(.plain)
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
        }
        #endif
    }

    // E24.2-fix: AI-popover-inhoud — DS-typografie, Pro via DSProChip (zoals
    // elders), zelfde look als de Background/Adjust-popovers.
    private var aiMenu: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            aiItem("Improve lighting", pro: false, action: onImproveLighting)
            aiItem("Colorise", pro: !isPro, action: onColorise)
            aiItem("Boost resolution", pro: !isPro, action: onBoost)
        }
    }

    private func aiItem(_ title: String, pro: Bool, action: @escaping () -> Void) -> some View {
        Button {
            showAI = false
            action()
        } label: {
            HStack(spacing: DSSpacing.gap2) {
                Text(title)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                Spacer(minLength: DSSpacing.gap2)
                if pro { DSProChip() }
            }
            .padding(.horizontal, DSSpacing.gap3)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle().fill(DSColor.Foreground.divider).frame(width: 1, height: 20)
            .padding(.horizontal, DSSpacing.gap1)
    }

    /// Knop met optionele handler (nil → gedimde stub).
    private func item(_ title: String, systemImage: String, action: (() -> Void)?) -> some View {
        button(title, systemImage: systemImage) { action?() }
            .disabled(action == nil)
            .opacity(action == nil ? 0.45 : 1)
    }

    private func button(_ title: String, systemImage: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { label(title, systemImage: systemImage, isActive: isActive) }
            .buttonStyle(.plain)
    }

    private func label(_ title: String, systemImage: String, isActive: Bool = false, chevron: Bool = false) -> some View {
        HStack(spacing: DSSpacing.gap1) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .medium))
            Text(title).dsTextStyle(.labelSmall)
            if chevron { Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
        }
        .foregroundStyle(DSColor.Foreground.primary)
        .padding(.horizontal, DSSpacing.gap2)
        .frame(height: 32)
        .background(isActive ? DSColor.Background.neutralStronger : .clear, in: Capsule())
    }
}
