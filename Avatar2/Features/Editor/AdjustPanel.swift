// Adjust-paneel — handmatige color-correctie als compacte toolbar-tool.
// Icoonrij (Brightness/Contrast/Saturation/Temperature) + één actieve slider,
// geïnspireerd op iOS Photos Adjust, passend in DSEditPanel-chrome.
// Live preview via onPreview; loslaten van de slider commit een undo-bare
// stap (onCommit before→after). Reset zet alles neutraal.
//
// Figma-TODO: er is (nog) geen DS-slider-component; dit gebruikt SwiftUI's
// Slider met DS-tint. Vervangen zodra de slider in de library staat.

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

    private func isDirty(_ property: Property) -> Bool {
        switch property {
        case .brightness: brightness != property.neutral
        case .contrast: contrast != property.neutral
        case .saturation: saturation != property.neutral
        case .temperature: temperature != property.neutral
        }
    }

    var body: some View {
        VStack(spacing: DSSpacing.gap4) {
            propertyIconRow

            VStack(spacing: DSSpacing.gap2) {
                Slider(
                    value: activeBinding,
                    in: selected.range,
                    onEditingChanged: { editing in
                        if editing {
                            dragStart = current
                        } else if let before = dragStart {
                            onCommit(before, current)
                            dragStart = nil
                        }
                    }
                )
                .id(selected)
                .controlSize(.small)
                .tint(DSColor.Action.primary)

                Text(displayValue == 0 ? "0" : String(format: "%+d", displayValue))
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
            }
            .onChange(of: brightness) { _, _ in schedulePreview() }
            .onChange(of: contrast) { _, _ in schedulePreview() }
            .onChange(of: saturation) { _, _ in schedulePreview() }
            .onChange(of: temperature) { _, _ in schedulePreview() }

            HStack {
                DSGhostButton("Reset") { reset() }
                    .disabled(!hasAdjustments)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
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
        }
    }

    private var propertyIconRow: some View {
        HStack(spacing: 0) {
            ForEach(Property.allCases) { property in
                propertyButton(property)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func propertyButton(_ property: Property) -> some View {
        let isSelected = selected == property
        return Button {
            selected = property
        } label: {
            VStack(spacing: DSSpacing.gap1) {
                ZStack {
                    Circle()
                        .fill(DSColor.Background.neutral)
                        .frame(width: 44, height: 44)
                    if isSelected {
                        Circle()
                            .strokeBorder(DSColor.Action.primary, lineWidth: 2)
                            .frame(width: 44, height: 44)
                    }
                    Image(systemName: property.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSelected
                                         ? DSColor.Action.primary
                                         : DSColor.Foreground.muted)
                }
                Text(property.label)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(isSelected
                                     ? DSColor.Action.primary
                                     : DSColor.Foreground.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Circle()
                    .fill(isDirty(property) ? DSColor.Foreground.primary : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
        .dsHoverScale()
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
        onPreview(source)
        onCommit(before, .neutral)
    }
}
