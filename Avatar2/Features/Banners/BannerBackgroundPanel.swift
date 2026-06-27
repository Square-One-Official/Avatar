// E37.3 — Background/Fill-paneel van de Banner Studio.

import AppKit
import AvatarUI
import SwiftUI

struct BannerBackgroundPanel: View {
    @Bindable var doc: BannerDoc
    var subtitle: String?

    @State private var brand = BrandColorKit.shared
    @State private var customImages = BackgroundImageKit.shared
    @State private var showColorPicker = false
    @State private var pickerColor: Color = .white

    private let swatch: CGFloat = 30

    var body: some View {
        DSEditPanel(title: "Background", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                section("Color") { colorRow }
                section("Gradient") { gradientRow }
                section("Image") { imageRow }
                if isImageFillActive {
                    zoomRow
                }
                Text("Tap the canvas to add a photo — drag to reframe when selected.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
            .help("Upload image")

            if let data = doc.fillImageData,
               isImageFillActive,
               kitIDMatchingCurrentFill() == nil,
               let image = NSImage(data: data) {
                imageSwatchButton(image: image, selected: true) {
                    doc.applyFillImage(data, resetFraming: false)
                }
            }

            ForEach(customImages.imageIDs, id: \.self) { id in
                if let image = customImages.image(for: id) {
                    let selected = isImageFillActive && kitIDMatchingCurrentFill() == id
                    imageSwatchButton(image: image, selected: selected) {
                        selectCustomImage(id)
                    }
                }
            }
        }
    }

    private var zoomRow: some View {
        HStack(spacing: DSSpacing.gap2) {
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(DSColor.Foreground.muted)
            DSSlider(value: zoomBinding, in: 1...3)
                .frame(maxWidth: 180)
        }
    }

    private var zoomBinding: Binding<Double> {
        Binding(
            get: { doc.fillImageZoom },
            set: { newValue in
                doc.fillImageZoom = newValue
                doc.touch()
            }
        )
    }

    private func imageSwatchButton(image: NSImage, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .fill(DSColor.Background.neutral)
                .frame(width: swatch, height: swatch)
                .overlay {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .strokeBorder(
                            selected ? DSColor.Action.primary : DSColor.Foreground.divider,
                            lineWidth: selected ? DSBorderWidth.medium : DSBorderWidth.thin
                        )
                )
        }
        .buttonStyle(.plain)
        .dsHoverScale()
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

    private var isImageFillActive: Bool {
        if case .image = doc.layers.fill, doc.fillImageData != nil { return true }
        return false
    }

    private func kitIDMatchingCurrentFill() -> String? {
        guard let data = doc.fillImageData else { return nil }
        return customImages.imageIDs.first { customImages.data(for: $0) == data }
    }

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

    private func uploadCustom() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let raw = try? Data(contentsOf: url) else { return }
        let stored = customImages.add(raw) ?? raw
        doc.applyFillImage(stored)
    }

    private func selectCustomImage(_ id: String) {
        guard let data = customImages.data(for: id) else { return }
        doc.applyFillImage(data, resetFraming: false)
    }
}
