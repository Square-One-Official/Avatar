// E37.3 — Background/Fill-paneel van de Banner Studio.

import AppKit
import AvatarUI
import SwiftUI

struct BannerBackgroundPanel: View {
    @Bindable var doc: BannerDoc
    var subtitle: String?

    @State private var brand = BrandColorKit.shared
    @State private var showColorPicker = false
    @State private var pickerColor: Color = .white

    private let swatch: CGFloat = 30

    var body: some View {
        DSEditPanel(title: "Background", subtitle: subtitle) {
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

    private func scrollRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.gap2) { content() }
                .padding(.vertical, DSSpacing.gap2)
                .padding(.leading, DSSpacing.gap1)
                .scrollRowTrailingInset()
        }
        .horizontalScrollEdgeFade()
    }

    // MARK: Color

    private var colorRow: some View {
        scrollRow {
            Button {
                if let c = currentSolidColor { pickerColor = c }
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
                    .appliedAppearancePreference()
            }

            ForEach(Array(BackgroundKit.colorPresets.enumerated()), id: \.offset) { _, color in
                swatchButton(color) { applySolid(color) }
            }
            ForEach(brand.hexColors, id: \.self) { hex in
                if let color = Color(hexRGB: hex) {
                    swatchButton(color) { applySolid(color) }
                }
            }
        }
        .onChange(of: pickerColor) { _, c in
            guard showColorPicker else { return }
            applySolid(c)
        }
        .onChange(of: showColorPicker) { _, open in
            if !open, let hex = pickerColor.hexRGB { brand.add(hex) }
        }
    }

    // MARK: Gradient

    private var gradientRow: some View {
        scrollRow {
            ForEach(Array(BackgroundKit.gradientPresets.enumerated()), id: \.offset) { _, colors in
                Button { applyGradient(colors) } label: {
                    RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                        .fill(BackgroundKit.gradient(colors))
                        .frame(width: 96, height: swatch)
                        .overlay(
                            RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                                .strokeBorder(
                                    isSelectedGradient(colors) ? DSColor.Action.primary : DSColor.Foreground.divider,
                                    lineWidth: isSelectedGradient(colors) ? DSBorderWidth.medium : DSBorderWidth.thin
                                )
                        )
                }
                .buttonStyle(.plain)
                .dsHoverScale()
            }
        }
    }

    // MARK: Image

    private var imageRow: some View {
        HStack(spacing: DSSpacing.gap2) {
            DSNeutralButton("Upload image") { upload() }
            if doc.layers.fill == .image, let data = doc.fillImageData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: swatch * 1.6, height: swatch)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                            .strokeBorder(DSColor.Action.primary, lineWidth: DSBorderWidth.medium)
                    )
            }
            if doc.layers.fill == .image, doc.fillImageData != nil {
                Text("Drag on canvas to reframe.")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
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

    private func isSelectedGradient(_ colors: [Color]) -> Bool {
        guard case let .meshGradient(stops) = doc.layers.fill else { return false }
        let hexes = colors.compactMap { $0.hexRGB }
        guard hexes.count >= 2, stops.count >= 2 else { return false }
        return stops.first?.hex.caseInsensitiveCompare(hexes[0]) == .orderedSame
            && stops.last?.hex.caseInsensitiveCompare(hexes[hexes.count - 1]) == .orderedSame
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
        doc.fillImageFocalX = 0.5
        doc.fillImageFocalY = 0.5
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
