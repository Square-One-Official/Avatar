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
    /// E24.14: de RAUWE cutout (zonder Adjust-laag). De sliders renderen er live
    /// bovenop; de commit persisteert alléén de params (niet-destructief).
    let source: NSImage
    /// E24.14: de persisted Adjust-stand bij het openen — heropenen toont 'm.
    var initial: PortraitAdjust = .neutral
    var onPreview: (NSImage) -> Void = { _ in }
    /// E24.14: commit levert de param-stand (before→after) i.p.v. beelden, zodat
    /// de caller ze niet-destructief op het portret kan persisteren + undo'en.
    var onCommit: (_ before: PortraitAdjust, _ after: PortraitAdjust) -> Void = { _, _ in }
    var onImproveLighting: () -> Void = {}
    var onColorise: () -> Void = {}
    var onBoost: () -> Void = {}
    var isPro: Bool = false
    /// E24.3: in de Adjust-popover staat de AI-dropdown apart (canvas-toolbar),
    /// dus dan tonen we alléén de sliders + Reset.
    var showAutoEnhance: Bool = true

    @State private var seeded = false
    @State private var brightness = 0.0
    @State private var contrast = 1.0
    @State private var saturation = 1.0
    @State private var temperature = 0.0
    /// Param-stand bij het begin van een sleep (voor de undo-bare commit).
    @State private var dragStart: PortraitAdjust?

    private var current: PortraitAdjust {
        PortraitAdjust(brightness: brightness, contrast: contrast,
                       saturation: saturation, temperature: temperature)
    }

    private var hasAdjustments: Bool { !current.isNeutral }

    private func adjusted() -> NSImage {
        guard !current.isNeutral,
              let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let out = PortraitEnhancer.colorAdjust(
                cg, brightness: brightness, contrast: contrast,
                saturation: saturation, temperatureShift: temperature
              ) else { return source }
        return NSImage(cgImage: out, size: source.size)
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
        .onAppear {
            // Seed de sliders eenmalig op de persisted stand (heropenen toont 'm).
            guard !seeded else { return }
            brightness = initial.brightness
            contrast = initial.contrast
            saturation = initial.saturation
            temperature = initial.temperature
            seeded = true
        }
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
                        dragStart = current
                    } else if let before = dragStart {
                        onCommit(before, current)
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
        let before = current
        brightness = 0; contrast = 1; saturation = 1; temperature = 0
        onPreview(source)
        onCommit(before, .neutral)
    }
}
