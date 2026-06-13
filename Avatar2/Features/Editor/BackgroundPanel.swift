// Background-paneel (E07.1, Figma App / Choose Background 4017:1099).
// Twee secties: "Image" (+ custom upload, gegenereerde gradient-presets)
// en "Color" (DS-projectkleur-presets + persistente brand colors + een
// eyedropper). Een keuze schrijft op het Portrait2 (kleur xor afbeelding);
// het canvas toont de achtergrond live (E07.2 doet de exportkwaliteit-
// compositing). Tegelijk gaat het dot-grid uit.

import AppKit
import AvatarUI
import SwiftUI

struct BackgroundPanel: View {
    let portrait: Portrait2?
    @State private var brand = BrandColorKit.shared

    private let swatch: CGFloat = 36

    var body: some View {
        DSEditPanel(title: "Background") {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                section("Image") { imageRow }
                section("Color") { colorRow }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            Text(title)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
            content()
        }
    }

    // MARK: Image-rij — upload + gradient-presets

    private var imageRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.gap2) {
                Button(action: uploadCustom) {
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .fill(DSColor.Background.neutral)
                        .frame(width: swatch, height: swatch)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DSColor.Foreground.subtle)
                        }
                }
                .buttonStyle(.plain)

                ForEach(Array(BackgroundKit.gradientPresets.enumerated()), id: \.offset) { _, colors in
                    Button { selectGradient(colors) } label: {
                        RoundedRectangle(cornerRadius: DSRadius.lg)
                            .fill(BackgroundKit.gradient(colors))
                            .frame(width: swatch, height: swatch)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Color-rij — presets + brand + eyedropper

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.gap2) {
                ForEach(Array(BackgroundKit.colorPresets.enumerated()), id: \.offset) { _, color in
                    colorSwatch(color)
                }
                ForEach(brand.hexColors, id: \.self) { hex in
                    if let color = Color(hexRGB: hex) { colorSwatch(color, hex: hex) }
                }
                Button(action: sampleColor) {
                    Circle()
                        .fill(DSColor.Background.neutral)
                        .frame(width: swatch, height: swatch)
                        .overlay {
                            Image(systemName: "eyedropper")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DSColor.Foreground.subtle)
                        }
                }
                .buttonStyle(.plain)
                .help("Pick a brand colour")
            }
        }
    }

    private func colorSwatch(_ color: Color, hex providedHex: String? = nil) -> some View {
        let hex = providedHex ?? color.hexRGB
        let isSelected = hex != nil && portrait?.backgroundColorHex == hex
        return Button { if let hex { selectColor(hex) } } label: {
            Circle()
                .fill(color)
                .frame(width: swatch, height: swatch)
                .overlay {
                    Circle().strokeBorder(DSColor.Foreground.primary,
                                          lineWidth: isSelected ? 2 : 0)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Acties

    private func selectColor(_ hex: String) {
        guard let portrait else { return }
        portrait.backgroundColorHex = hex
        portrait.backgroundImageData = nil
        portrait.touch()
    }

    private func selectGradient(_ colors: [Color]) {
        guard let portrait, let png = BackgroundKit.renderGradientPNG(colors) else { return }
        portrait.backgroundImageData = png
        portrait.backgroundColorHex = nil
        portrait.touch()
    }

    private func uploadCustom() {
        guard let portrait else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        portrait.backgroundImageData = data
        portrait.backgroundColorHex = nil
        portrait.touch()
    }

    private func sampleColor() {
        NSColorSampler().show { picked in
            guard let picked, let hex = Color(picked).hexRGB else { return }
            brand.add(hex)
            selectColor(hex)
        }
    }
}
