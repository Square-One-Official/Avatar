// Edit-paneel (E22.3) — live handmatige color-correctie. Vier sliders
// (Brightness/Contrast/Saturation/Temperature) passen meteen toe op de canvas
// (goedkope preview via onPreview); op het loslaten van een slider commit een
// undo-bare stap (onCommit before→after). Reset zet alles neutraal. De
// AI-acties (Improve lighting/Colorise/Boost) zitten onder een "Auto enhance"-
// dropdown vanuit de Edit-bar.
//
// Figma-TODO: er is (nog) geen DS-slider-component; dit gebruikt SwiftUI's
// Slider met DS-tint. Vervangen zodra de slider in de library staat.

import AvatarKit
import AvatarUI
import SwiftUI

struct EditColorPanel: View {
    /// Cutout bij het openen van de sessie (wordt eenmalig de basis).
    let source: NSImage
    var onPreview: (NSImage) -> Void = { _ in }
    var onCommit: (_ before: NSImage, _ after: NSImage) -> Void = { _, _ in }
    var onImproveLighting: () -> Void = {}
    var onColorise: () -> Void = {}
    var onBoost: () -> Void = {}
    var isPro: Bool = false
    /// E24.3: in de Adjust-popover staat de AI-dropdown apart (canvas-toolbar),
    /// dus dan tonen we alléén de sliders + Reset.
    var showAutoEnhance: Bool = true

    @State private var base: NSImage?
    @State private var brightness = 0.0
    @State private var contrast = 1.0
    @State private var saturation = 1.0
    @State private var temperature = 0.0
    @State private var dragStart: NSImage?

    private var hasAdjustments: Bool {
        brightness != 0 || contrast != 1 || saturation != 1 || temperature != 0
    }

    private func adjusted() -> NSImage {
        let ref = base ?? source
        guard let cg = ref.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let out = PortraitEnhancer.colorAdjust(
                cg, brightness: brightness, contrast: contrast,
                saturation: saturation, temperatureShift: temperature
              ) else { return ref }
        return NSImage(cgImage: out, size: ref.size)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            slider("Brightness", value: $brightness, range: -0.4...0.4)
            slider("Contrast", value: $contrast, range: 0.6...1.4)
            slider("Saturation", value: $saturation, range: 0...2)
            slider("Temperature", value: $temperature, range: -1...1)

            HStack(spacing: DSSpacing.gap3) {
                DSGhostButton("Reset") { reset() }
                    .disabled(!hasAdjustments)
                Spacer()
                if showAutoEnhance { autoEnhanceMenu }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if base == nil { base = source } }
    }

    private var autoEnhanceMenu: some View {
        Menu {
            Button("Improve lighting", action: onImproveLighting)
            Button(isPro ? "Colorise" : "Colorise · Pro", action: onColorise)
            Button(isPro ? "Boost resolution" : "Boost resolution · Pro", action: onBoost)
        } label: {
            HStack(spacing: DSSpacing.gap1) {
                DSIcon(.sparkle, size: 16)
                Text("Auto enhance").dsTextStyle(.labelBase)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap3)
            .frame(height: 36)
            .background(DSColor.Background.neutral, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            Text(label)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
            Slider(
                value: value,
                in: range,
                onEditingChanged: { editing in
                    if editing {
                        dragStart = adjusted()
                    } else if let before = dragStart {
                        onCommit(before, adjusted())
                        dragStart = nil
                    }
                }
            )
            .controlSize(.small)
            .tint(DSColor.Action.primary)
            .onChange(of: value.wrappedValue) { _, _ in onPreview(adjusted()) }
        }
    }

    private func reset() {
        let before = adjusted()
        brightness = 0; contrast = 1; saturation = 1; temperature = 0
        let after = base ?? source
        onPreview(after)
        onCommit(before, after)
    }
}
