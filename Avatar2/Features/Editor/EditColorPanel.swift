// Edit-paneel (E22.3) — live handmatige color-correctie. Vier sliders
// (Brightness/Contrast/Saturation/Temperature) passen meteen toe op de canvas
// (goedkope preview via onPreview); op het loslaten van een slider commit een
// undo-bare stap (onCommit before→after). Reset zet alles neutraal.
// De één-tik-acties (One click retouch/Studio Light/Colorise/Boost/Restore body)
// staan als compacte chips bovenin het Enhance-paneel. One-click retouch verhuisde
// hierheen uit het Face-paneel (Thierry, 2026-06-23).
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
    /// One-click retouch (lokaal) — verhuisd uit Face (Thierry, 2026-06-23). Toont
    /// als eerste chip wanneer `showRetouch`.
    var onRetouch: () -> Void = {}
    var onStudioLight: () -> Void = {}
    /// Portrait-modus (achtergrond-blur) aan/uit — verhuist niet, blurt de
    /// achtergrondLAAG en houdt het onderwerp scherp (macOS-webcam-Portrait).
    var onPortrait: () -> Void = {}
    var onColorise: () -> Void = {}
    var onBoost: () -> Void = {}
    // E31.3: Restore body verhuisde mee uit de frame-toolbar-AI-dropdown.
    var onRestoreBody: () -> Void = {}
    var isPro: Bool = false
    /// E24.28: of de lokale "Studio Light"-toggle momenteel AAN staat.
    var studioLightOn: Bool = false
    /// Of "Portrait" (achtergrond-blur) momenteel AAN staat.
    var portraitOn: Bool = false
    /// One-click retouch-toggle AAN (editor); op de board een one-shot (false).
    var retouchOn: Bool = false
    /// Toon de "One click retouch"-chip als eerste in de één-tik-rij. Default uit
    /// zodat de board batch-adjust 'm niet toont (retouch = per beeld).
    var showRetouch: Bool = false
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
    /// Perf: de bron-CGImage één keer gedecodeerd zodat de live preview niet
    /// elke slider-tik opnieuw decodeert.
    @State private var sourceCG: SendableCGImage?
    /// Lopende off-main preview-render; bij elke nieuwe tik gecanceld zodat
    /// alleen de laatste stand landt (coalescing).
    @State private var previewTask: Task<Void, Never>?

    private var current: PortraitAdjust {
        PortraitAdjust(brightness: brightness, contrast: contrast,
                       saturation: saturation, temperature: temperature)
    }

    private var hasAdjustments: Bool { !current.isNeutral }

    /// Live preview off-main (perf): de kleuraanpassing draaide voorheen
    /// synchroon op de main-thread bij élke slider-tik (vol-res CIContext-render
    /// → hapert). Nu: één gedeelde decode, render op een achtergrond-executor,
    /// plus korte debounce + cancel zodat alleen de laatste stand landt.
    /// Neutraal toont direct de rauwe cutout.
    @MainActor
    private func schedulePreview() {
        previewTask?.cancel()
        let adj = current
        guard !adj.isNeutral, let boxed = sourceCG else {
            previewTask = nil
            onPreview(source)
            return
        }
        let size = source.size
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000) // ~12 ms coalescing
            if Task.isCancelled { return }
            guard let out = await Self.renderAdjust(boxed, adj),
                  !Task.isCancelled else { return }
            onPreview(NSImage(cgImage: out.cgImage, size: size))
        }
    }

    private nonisolated static func renderAdjust(
        _ boxed: SendableCGImage, _ adj: PortraitAdjust
    ) async -> SendableCGImage? {
        PortraitEnhancer.colorAdjust(
            boxed.cgImage, brightness: adj.brightness, contrast: adj.contrast,
            saturation: adj.saturation, temperatureShift: adj.temperature
        ).map(SendableCGImage.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            // E24.27: één-tik AI-acties bovenin als compacte DS-chips (Pro/credit
            // waar van toepassing) → divider → de manuele sliders eronder.
            if showAutoEnhance {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.gap2) {
                        // One-click retouch verhuisde hierheen uit Face — eerste chip.
                        if showRetouch {
                            quickAction("One click retouch", icon: "wand.and.stars", isOn: retouchOn, action: onRetouch)
                        }
                        quickAction("Studio Light", icon: "sun.max", isOn: studioLightOn, action: onStudioLight)
                        // Portrait: vervaagt de achtergrond (origineel/custom), onderwerp scherp.
                        quickAction("Portrait", icon: "camera.aperture", isOn: portraitOn, action: onPortrait)
                        quickAction("Colorise", icon: "paintbrush.pointed", pro: !isPro, action: onColorise)
                        quickAction("Boost", icon: "arrow.up.backward.and.arrow.down.forward",
                                    credit: CreditMeter.chipLabel(for: .upscale), action: onBoost)
                        // E31.3: Restore body uit de oude frame-toolbar-AI-dropdown.
                        quickAction("Restore body", icon: "person.crop.rectangle", pro: !isPro, action: onRestoreBody)
                    }
                    .padding(.vertical, DSSpacing.gap1)
                    .scrollRowTrailingInset()
                }
                .horizontalScrollEdgeFade()
                Divider()
            }

            slider("Brightness", value: $brightness, range: -0.4...0.4)
            slider("Contrast", value: $contrast, range: 0.6...1.4)
            slider("Saturation", value: $saturation, range: 0...2)
            slider("Temperature", value: $temperature, range: -1...1)

            HStack(spacing: DSSpacing.gap3) {
                DSGhostButton("Reset") { reset() }
                    .disabled(!hasAdjustments)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if sourceCG == nil,
               let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                sourceCG = SendableCGImage(cgImage: cg)
            }
            // Seed de sliders eenmalig op de persisted stand (heropenen toont 'm).
            guard !seeded else { return }
            brightness = initial.brightness
            contrast = initial.contrast
            saturation = initial.saturation
            temperature = initial.temperature
            seeded = true
        }
    }

    /// E24.27/24.28: compacte één-tik-actie-chip met optionele Pro-badge/credit
    /// en — voor toggle-acties — een duidelijke active-state (lime fill + check).
    private func quickAction(_ label: String, icon: String, pro: Bool = false,
                             credit: String? = nil, isOn: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap1) {
                Image(systemName: isOn ? "checkmark" : icon).font(.system(size: 12, weight: .medium))
                Text(label).dsTextStyle(.labelSmall)
                if pro {
                    DSProChip()
                } else if let credit {
                    DSBadge(credit, type: .neutral, compact: true)
                }
            }
            // E24.28: lime fill + onAction-tekst als de toggle AAN staat.
            .foregroundStyle(isOn ? DSColor.Action.onAction : DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 32)
            .background(isOn ? DSColor.Action.primary : DSColor.Background.neutral, in: Capsule())
        }
        .buttonStyle(.plain)
        .dsHoverScale()
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
            .onChange(of: value.wrappedValue) { _, _ in schedulePreview() }
        }
    }

    private func reset() {
        let before = current
        previewTask?.cancel()
        brightness = 0; contrast = 1; saturation = 1; temperature = 0
        onPreview(source)
        onCommit(before, .neutral)
    }
}
