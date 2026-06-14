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
    // E24.24: persistente custom-achtergrond-uploads (herbruikbare swatches).
    @State private var customImages = BackgroundImageKit.shared
    // E25.2: DSColorPicker vanuit de "+"-knop in de Color-rij.
    @State private var showColorPicker = false
    @State private var pickerColor: Color = .white

    private let swatch: CGFloat = 36

    var body: some View {
        // E24-fix: in de canvas-toolbar-popover tonen we de inhoud direct
        // (zoals de Adjust-popover), niet in een tweede DSEditPanel-kaart —
        // de popover ís de kaart. Rijen scrollen met rand-inset + fade.
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            section("Image") { imageRow }
            section("Color") { colorRow }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// E24-fix: rechter-rand-fade als scroll-affordance + trailing-inset zodat
    /// geen swatch hard tegen de rand wordt afgesneden. E24.10: verticale +
    /// leading-padding zodat de hover-scale van een swatch niet wordt afgekapt
    /// door de scroll-/mask-grens.
    private func scrollRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.gap2) { content() }
                .padding(.vertical, DSSpacing.gap2)
                .padding(.leading, DSSpacing.gap1)
                .padding(.trailing, DSSpacing.gap4)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
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
        scrollRow {
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
            .dsHoverScale()

            // E24.24: persistente custom-uploads als herbruikbare swatches.
            ForEach(customImages.imageIDs, id: \.self) { id in
                if let image = customImages.image(for: id) {
                    Button { selectCustomImage(id) } label: {
                        RoundedRectangle(cornerRadius: DSRadius.lg)
                            .fill(DSColor.Background.neutral)
                            .frame(width: swatch, height: swatch)
                            .overlay {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                    }
                    .buttonStyle(.plain)
                    .dsHoverScale()
                }
            }

            ForEach(Array(BackgroundKit.gradientPresets.enumerated()), id: \.offset) { _, colors in
                Button { selectGradient(colors) } label: {
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .fill(BackgroundKit.gradient(colors))
                        .frame(width: swatch, height: swatch)
                }
                .buttonStyle(.plain)
                .dsHoverScale()
            }
        }
    }

    // MARK: Color-rij — "+" (DSColorPicker) + presets + brand

    private var colorRow: some View {
        scrollRow {
            // E25.2: "+"-knop HELEMAAL LINKS opent de DSColorPicker (met eigen
            // eyedropper). De losse eyedropper-knop is vervallen.
            Button {
                if let hex = portrait?.backgroundColorHex, let c = Color(hexRGB: hex) { pickerColor = c }
                showColorPicker = true
            } label: {
                Circle()
                    .fill(DSColor.Background.neutral)
                    .frame(width: swatch, height: swatch)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DSColor.Foreground.subtle)
                    }
            }
            .buttonStyle(.plain)
            .dsHoverScale()
            .help("Pick a colour")
            .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                DSColorPicker(color: $pickerColor, supportsAlpha: false)
                    .padding(DSSpacing.gap3)
            }

            ForEach(Array(BackgroundKit.colorPresets.enumerated()), id: \.offset) { _, color in
                colorSwatch(color)
            }
            ForEach(brand.hexColors, id: \.self) { hex in
                if let color = Color(hexRGB: hex) { colorSwatch(color, hex: hex) }
            }
        }
        // E25.2: live de achtergrond bijwerken terwijl de picker open is.
        .onChange(of: pickerColor) { _, c in
            guard showColorPicker, let hex = c.hexRGB else { return }
            selectColor(hex)
        }
        // Bij sluiten: de gekozen kleur als persistente brand-swatch bewaren.
        .onChange(of: showColorPicker) { _, open in
            if !open, let hex = pickerColor.hexRGB { brand.add(hex) }
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
        .dsHoverScale()
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
        // E24.24: persistent opslaan als herbruikbare swatch (+ downscale, 24.23);
        // de teruggegeven PNG wordt meteen de achtergrond.
        let stored = customImages.add(data) ?? data
        portrait.backgroundImageData = stored
        portrait.backgroundColorHex = nil
        portrait.touch()
    }

    /// E24.24: kies een eerder geüploade (persistente) achtergrond-swatch.
    private func selectCustomImage(_ id: String) {
        guard let portrait, let data = customImages.data(for: id) else { return }
        portrait.backgroundImageData = data
        portrait.backgroundColorHex = nil
        portrait.touch()
    }

}
