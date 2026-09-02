// Adjust-paneel — handmatige color-correctie als compacte toolbar-tool.
// Icoonrij (Brightness/Contrast/Saturation/Temperature) + één actieve slider,
// geïnspireerd op iOS Photos Adjust, passend in DSEditPanel-chrome.
// Live preview via onPreview; loslaten van de slider commit een undo-bare
// stap (onCommit before→after). Reset (header, rechtsboven) zet alles neutraal.

import AvatarKit
import AvatarUI
import SwiftUI

struct AdjustPanel: View {
    /// De RAUWE cutout (zonder Adjust-laag). De slider rendert er live bovenop;
    /// de commit persisteert alléén de params (niet-destructief).
    let source: NSImage
    /// Persisted Adjust-stand bij het openen — heropenen toont 'm.
    var initial: PortraitAdjust = .neutral
    var onPreview: (NSImage) -> Void = { _ in }
    /// Commit levert de param-stand (before→after) i.p.v. beelden.
    var onCommit: (_ before: PortraitAdjust, _ after: PortraitAdjust) -> Void = { _, _ in }
    var maxWidth: CGFloat = 600
    var maxContentHeight: CGFloat = 220

    private enum Property: String, CaseIterable, Identifiable {
        case brightness, contrast, saturation, temperature

        var id: String { rawValue }

        var label: String {
            switch self {
            case .brightness: "Brightness"
            case .contrast: "Contrast"
            case .saturation: "Saturation"
            case .temperature: "Temperature"
            }
        }

        var icon: String {
            switch self {
            case .brightness: "sun.max"
            case .contrast: "circle.lefthalf.filled"
            case .saturation: "drop"
            case .temperature: "thermometer.medium"
            }
        }

        var range: ClosedRange<Double> {
            switch self {
            case .brightness: -0.4...0.4
            case .contrast: 0.6...1.4
            case .saturation: 0...2
            case .temperature: -1...1
            }
        }

        var neutral: Double {
            switch self {
            case .brightness, .temperature: 0
            case .contrast, .saturation: 1
            }
        }

        /// Display-eenheden van 10 (Brightness −40…40, Saturation −100…100).
        var step: Double { 0.1 }

        var track: DSSlider.Track {
            switch self {
            case .brightness:
                .gradient([
                    Color(red: 0.08, green: 0.08, blue: 0.08),
                    Color(red: 0.96, green: 0.96, blue: 0.94),
                ])
            case .contrast:
                .gradient([
                    Color(red: 0.96, green: 0.96, blue: 0.94),
                    Color(red: 0.08, green: 0.08, blue: 0.08),
                ])
            case .saturation:
                .gradient([
                    Color(red: 0.62, green: 0.62, blue: 0.62),
                    Color(red: 0.55, green: 0.35, blue: 0.95),
                    Color(red: 0.95, green: 0.35, blue: 0.55),
                    Color(red: 0.95, green: 0.75, blue: 0.20),
                    DSColor.Action.primary,
                ])
            case .temperature:
                .gradient([
                    Color(red: 0.35, green: 0.62, blue: 0.98),
                    Color(red: 0.92, green: 0.92, blue: 0.90),
                    Color(red: 0.98, green: 0.72, blue: 0.28),
                ])
            }
        }
    }

    @State private var seeded = false
    @State private var selected: Property = .brightness
    @State private var brightness = 0.0
    @State private var contrast = 1.0
    @State private var saturation = 1.0
    @State private var temperature = 0.0
    /// Param-stand bij het begin van een sleep (voor de undo-bare commit).
    @State private var dragStart: PortraitAdjust?
    /// Perf: bron-CGImage één keer gedecodeerd voor live preview.
    @State private var sourceCG: SendableCGImage?
    /// Lopende off-main preview-render; bij elke nieuwe tik gecanceld.
    @State private var previewTask: Task<Void, Never>?
    /// Concept-tekst van het numerieke veld; commit op Return of focus-verlies.
    @State private var numericText = "0"
    @FocusState private var numericFocused: Bool

    private var current: PortraitAdjust {
        PortraitAdjust(brightness: brightness, contrast: contrast,
                       saturation: saturation, temperature: temperature)
    }

    private var hasAdjustments: Bool { !current.isNeutral }

    private var activeBinding: Binding<Double> {
        switch selected {
        case .brightness: $brightness
        case .contrast: $contrast
        case .saturation: $saturation
        case .temperature: $temperature
        }
    }

    private var displayValue: Int {
        switch selected {
        case .brightness:
            return Int((brightness * 100).rounded())
        case .contrast:
            return Int(((contrast - 1) * 100).rounded())
        case .saturation:
            return Int(((saturation - 1) * 100).rounded())
        case .temperature:
            return Int((temperature * 100).rounded())
        }
    }

    private var formattedDisplay: String {
        displayValue == 0 ? "0" : String(format: "%+d", displayValue)
    }

    private var displayRange: ClosedRange<Int> {
        switch selected {
        case .brightness:
            return Int((selected.range.lowerBound * 100).rounded())
                ... Int((selected.range.upperBound * 100).rounded())
        case .contrast, .saturation:
            return Int(((selected.range.lowerBound - 1) * 100).rounded())
                ... Int(((selected.range.upperBound - 1) * 100).rounded())
        case .temperature:
            return Int((selected.range.lowerBound * 100).rounded())
                ... Int((selected.range.upperBound * 100).rounded())
        }
    }

    private func isDirty(_ property: Property) -> Bool {
        switch property {
        case .brightness: brightness != property.neutral
        case .contrast: contrast != property.neutral
        case .saturation: saturation != property.neutral
        case .temperature: temperature != property.neutral
        }
    }

    var body: some View {
        DSEditPanel(
            title: "Adjust",
            maxWidth: maxWidth,
            maxContentHeight: maxContentHeight,
            headerAccessory: { resetHeaderButton }
        ) {
            VStack(spacing: DSSpacing.gap4) {
                propertyIconRow

                VStack(spacing: DSSpacing.gap2) {
                    HStack(spacing: DSSpacing.gap2) {
                        DSSlider(
                            value: activeBinding,
                            in: selected.range,
                            track: selected.track,
                            step: selected.step,
                            onEditingChanged: { editing in
                                if editing {
                                    if numericFocused { commitNumeric() }
                                    numericFocused = false
                                    dragStart = current
                                } else if let before = dragStart {
                                    previewTask?.cancel()
                                    previewTask = nil
                                    onCommit(before, current)
                                    dragStart = nil
                                }
                            }
                        )
                        .id(selected)

                        numericField
                    }
                    .padding(.leading, DSSpacing.gap3)
                    .padding(.trailing, DSSpacing.gap2)
                    .padding(.vertical, DSSpacing.gap2)
                    .background(
                        DSColor.Background.inset,
                        in: Capsule()
                    )
                }
                .onChange(of: brightness) { _, _ in schedulePreview() }
                .onChange(of: contrast) { _, _ in schedulePreview() }
                .onChange(of: saturation) { _, _ in schedulePreview() }
                .onChange(of: temperature) { _, _ in schedulePreview() }
            }
            // Ruimte boven de icoonrij: scaleEffect telt niet in de layout, en
            // de ScrollView van DSEditPanel clipt overflow. Padding houdt de
            // ring + antialiasing binnen de clip-bounds.
            .padding(.top, DSSpacing.gap1)
            .onChange(of: selected) { _, _ in
                numericFocused = false
                numericText = formattedDisplay
            }
            .onChange(of: displayValue) { _, _ in
                if !numericFocused { numericText = formattedDisplay }
            }
        }
        .onAppear {
            if sourceCG == nil,
               let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                sourceCG = SendableCGImage(cgImage: cg)
            }
            guard !seeded else { return }
            brightness = initial.brightness
            contrast = initial.contrast
            saturation = initial.saturation
            temperature = initial.temperature
            seeded = true
            numericText = formattedDisplay
        }
        // E50.3: een Match lighting / undo terwijl het paneel open staat zet de
        // persisted stand om — de sliders volgen (niet midden in een sleep of
        // tijdens het typen in het numerieke veld).
        .onChange(of: initial) { _, updated in
            guard dragStart == nil, !numericFocused else { return }
            brightness = updated.brightness
            contrast = updated.contrast
            saturation = updated.saturation
            temperature = updated.temperature
            numericText = formattedDisplay
        }
        .onDisappear {
            previewTask?.cancel()
            previewTask = nil
        }
    }

    private var resetHeaderButton: some View {
        DSGhostButton("Reset", size: .small) { reset() }
            .disabled(!hasAdjustments)
            .help("Reset all adjustments")
    }

    private var numericField: some View {
        TextField("", text: $numericText)
            .textFieldStyle(.plain)
            .dsTextStyle(.labelBase)
            .foregroundStyle(DSColor.Foreground.primary)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: 44)
            .focused($numericFocused)
            .dsFocusEffectDisabled()
            .onSubmit { commitNumeric() }
            .onChange(of: numericFocused) { _, focused in
                if focused {
                    numericText = formattedDisplay
                } else {
                    commitNumeric()
                }
            }
            .accessibilityLabel(selected.label)
    }

    private var propertyIconRow: some View {
        HStack(spacing: 0) {
            ForEach(Property.allCases) { property in
                PropertyButton(
                    property: property,
                    isSelected: selected == property,
                    isDirty: isDirty(property)
                ) {
                    selected = property
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

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

    private func reset() {
        let before = current
        previewTask?.cancel()
        brightness = 0; contrast = 1; saturation = 1; temperature = 0
        numericText = formattedDisplay
        onPreview(source)
        onCommit(before, .neutral)
    }

    private func commitNumeric() {
        let parsed = Self.parseDisplay(numericText) ?? displayValue
        let clamped = min(displayRange.upperBound, max(displayRange.lowerBound, parsed))
        let before = current
        applyDisplay(clamped)
        numericText = formattedDisplay
        guard before != current else { return }
        previewTask?.cancel()
        previewTask = nil
        onCommit(before, current)
    }

    private func applyDisplay(_ display: Int) {
        let raw = Double(display) / 100
        switch selected {
        case .brightness: brightness = raw
        case .contrast: contrast = 1 + raw
        case .saturation: saturation = 1 + raw
        case .temperature: temperature = raw
        }
    }

    static func parseDisplay(_ text: String) -> Int? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("+") { trimmed.removeFirst() }
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    /// Icoon + label voor één Adjust-property. Hover kleurt de cirkel; we
    /// schalen alléén het SF-Symbol (binnen de 44pt-cirkel) zodat de ring
    /// niet uit de paneel-clip loopt.
    private struct PropertyButton: View {
        let property: Property
        let isSelected: Bool
        let isDirty: Bool
        let action: () -> Void

        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                VStack(spacing: DSSpacing.gap1) {
                    ZStack {
                        Circle()
                            .fill(hovering || isSelected
                                  ? DSColor.Background.neutralStronger
                                  : DSColor.Background.neutral)
                            .frame(width: 44, height: 44)
                        // Ring/inkt via primaryForeground (niet de lime-FILL):
                        // lime als inkt wast op de lichte card weg (~1.2:1),
                        // primaryForeground is dark = lime, light = brand-groen —
                        // zelfde patroon als DSToolButton/DSBottomToolbar.
                        if isSelected {
                            Circle()
                                .strokeBorder(DSColor.Action.primaryForeground,
                                              lineWidth: DSBorderWidth.medium)
                                .frame(width: 44, height: 44)
                        }
                        Image(systemName: property.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isSelected || hovering
                                             ? DSColor.Action.primaryForeground
                                             : DSColor.Foreground.primary)
                            .scaleEffect(hovering ? 1.08 : 1)
                    }
                    Text(property.label)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(isSelected
                                         ? DSColor.Action.primaryForeground
                                         : DSColor.Foreground.subtle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Circle()
                        .fill(isDirty ? DSColor.Foreground.primary : Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
            .onHover { hovering = $0 }
            .dsMotion(DSMotion.micro, value: hovering)
            .padding(.vertical, DSSpacing.gap1)
        }
    }
}
