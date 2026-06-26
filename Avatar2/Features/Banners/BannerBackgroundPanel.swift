// E37.3 — Background/Fill-paneel van de Banner Studio. Zet de banner-`fill`:
// solide kleur (brand-kleuren + DS-presets + picker), mesh-gradient-presets, of
// een geüploade afbeelding; plus een (gefaseerde) Generate-stub. Mutaties lopen
// via `BannerDoc.layers`/`fillImageData` → `touch()` → de Studio-canvas
// her-rendert (de preview hangt op `doc.updatedAt`). In de geest van de
// portret-`BackgroundPanel`, maar banner-specifiek.

import AppKit
import AvatarUI
import SwiftUI

struct BannerBackgroundPanel: View {
    @Bindable var doc: BannerDoc
    @State private var brand = BrandColorKit.shared

    private let swatch: CGFloat = 30

    var body: some View {
        DSEditPanel(title: "Background") {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                section("Color") { colorRow }
                section("Gradient") { gradientRow }
                section("Image") { imageRow }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            Text(title).dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.muted)
            content()
        }
    }

    // MARK: Color

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.gap2) {
                DSColorPicker(color: Binding(
                    get: { currentSolidColor ?? .white },
                    set: { applySolid($0, remember: true) }
                ), supportsAlpha: false)
                .frame(width: swatch, height: swatch)

                ForEach(Array(BackgroundKit.colorPresets.enumerated()), id: \.offset) { _, color in
                    swatchButton(color) { applySolid(color) }
                }
                ForEach(brand.hexColors, id: \.self) { hex in
                    if let color = Color(hexRGB: hex) {
                        swatchButton(color) { applySolid(color) }
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: Gradient

    private var gradientRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.gap2) {
                ForEach(Array(BackgroundKit.gradientPresets.enumerated()), id: \.offset) { _, colors in
                    Button { applyGradient(colors) } label: {
                        RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                            .fill(BackgroundKit.gradient(colors))
                            .frame(width: 96, height: swatch)
                            .overlay(
                                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                                    .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
                            )
                    }
                    .buttonStyle(.plain)
                    .dsHoverScale()
                }
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: Image

    private var imageRow: some View {
        HStack(spacing: DSSpacing.gap2) {
            DSNeutralButton("Upload image") { upload() }
            DSNeutralButton("Generate") { }
                .disabled(true)
                .help("AI banner generation — coming soon")
        }
    }

    // MARK: Swatch

    private func swatchButton(_ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: swatch, height: swatch)
                .overlay(
                    Circle().strokeBorder(
                        isSelectedSolid(color) ? DSColor.Action.primary : DSColor.Foreground.divider,
                        lineWidth: isSelectedSolid(color) ? DSBorderWidth.medium : DSBorderWidth.thin
                    )
                )
        }
        .buttonStyle(.plain)
        .dsHoverScale()
    }

    // MARK: State + apply

    private var currentSolidColor: Color? {
        if case let .solid(hex) = doc.layers.fill { return Color(hexRGB: hex) }
        return nil
    }

    private func isSelectedSolid(_ color: Color) -> Bool {
        guard case let .solid(hex) = doc.layers.fill else { return false }
        return color.hexRGB?.caseInsensitiveCompare(hex) == .orderedSame
    }

    private func applySolid(_ color: Color, remember: Bool = false) {
        guard let hex = color.hexRGB else { return }
        var layers = doc.layers
        layers.fill = .solid(hex: hex)
        doc.layers = layers
        if remember { brand.add(hex) }
    }

    private func applyGradient(_ colors: [Color]) {
        let hexes = colors.compactMap { $0.hexRGB }
        guard hexes.count >= 2 else { return }
        let stops = [
            MeshStop(hex: hexes[0], x: 0, y: 0),
            MeshStop(hex: hexes[hexes.count - 1], x: 1, y: 1),
        ]
        var layers = doc.layers
        layers.fill = .meshGradient(stops: stops)
        doc.layers = layers
    }

    private func applyImage(_ png: Data) {
        doc.fillImageData = png
        var layers = doc.layers
        layers.fill = .image
        doc.layers = layers
    }

    private func upload() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let raw = try? Data(contentsOf: url) else { return }
        let png = BackgroundKit.downscaledPNG(raw, maxSide: 2048) ?? raw
        applyImage(png)
    }
}
