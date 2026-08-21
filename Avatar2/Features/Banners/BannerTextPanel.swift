// E37.4 — Text-paneel van de Banner Studio. Voegt tekstlagen toe en bewerkt ze:
// inhoud, font, grootte, gewicht, kleur, uitlijning en verticale plaatsing.

import AppKit
import AvatarUI
import SwiftUI

struct BannerTextPanel: View {
    @Bindable var doc: BannerDoc
    @Binding var selectedLayerID: UUID?
    var presentation: UIPresentationStore
    var subtitle: String?

    @State private var texts: [BannerTextLayer] = []
    @State private var didLoad = false
    @State private var pickerColor: Color = .white

    private static let weights: [(Int, String)] = [(0, "Regular"), (1, "Medium"), (2, "Semibold"), (3, "Bold")]
    private let swatch: CGFloat = 28

    var body: some View {
        DSEditPanel(title: "Text", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                DSNeutralButton("Add text") { addText() }

                if texts.isEmpty {
                    Text("No text yet — add a line to start.")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach($texts) { $layer in
                        layerCard($layer)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsDropdownDismissOverlay(isPresented: fieldMenuDismiss)
        }
        .onChange(of: pickerColor) { _, c in
            guard case .bannerText(let id) = presentation.colorPicker else { return }
            guard let hex = c.hexRGB,
                  let index = texts.firstIndex(where: { $0.id == id }) else { return }
            texts[index].colorHex = hex
        }
        .onAppear {
            if !didLoad { texts = doc.layers.texts; didLoad = true }
        }
        .onChange(of: texts) { _, new in writeBack(new) }
        .onChange(of: selectedLayerID) { _, id in
            guard let id, !texts.contains(where: { $0.id == id }) else { return }
            selectedLayerID = texts.first?.id
        }
    }

    // MARK: Layer-kaart

    @ViewBuilder private func layerCard(_ layer: Binding<BannerTextLayer>) -> some View {
        let value = layer.wrappedValue
        let isSelected = selectedLayerID == value.id
        VStack(alignment: .leading, spacing: DSSpacing.gap3) {
            HStack(spacing: DSSpacing.gap2) {
                TextField("Your text", text: layer.string)
                    .textFieldStyle(.plain)
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .padding(.horizontal, DSSpacing.gap3)
                    .padding(.vertical, DSSpacing.gap2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                            .fill(DSColor.Background.neutral)
                    )

                Button { delete(value.id) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: DSIconSize.sm))
                        .foregroundStyle(DSColor.Foreground.muted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Delete text")
            }

            section("Font") {
                DSDropdownButton(
                    isPresented: fieldMenuOpen(.font(value.id)),
                    anchorHeight: 32,
                    minWidth: 200
                ) {
                    fieldMenuLabel(BannerFontCatalog.label(for: value.fontName))
                } menu: {
                    ForEach(BannerFontCatalog.curated) { entry in
                        DSMenuRow(
                            entry.label,
                            icon: "textformat",
                            shortcut: value.fontName == entry.fontName ? "✓" : nil
                        ) {
                            layer.wrappedValue.fontName = entry.fontName
                            presentation.bannerTextFieldMenu = nil
                        }
                    }
                }
            }

            section("Size") {
                HStack(spacing: DSSpacing.gap3) {
                    DSSlider(value: layer.fontSize, in: 24...max(240, value.fontSize))
                    Text("\(Int(value.fontSize))")
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
            }

            HStack(alignment: .top, spacing: DSSpacing.gap4) {
                section("Weight") {
                    DSDropdownButton(
                        isPresented: fieldMenuOpen(.weight(value.id)),
                        anchorHeight: 32,
                        minWidth: 160
                    ) {
                        fieldMenuLabel(weightLabel(value.weightRaw))
                    } menu: {
                        ForEach(Self.weights, id: \.0) { w in
                            DSMenuRow(
                                w.1,
                                icon: "bold",
                                shortcut: value.weightRaw == w.0 ? "✓" : nil
                            ) {
                                layer.wrappedValue.weightRaw = w.0
                                presentation.bannerTextFieldMenu = nil
                            }
                        }
                    }
                }

                section("Color") {
                    colorSwatch(layer)
                }
            }

            section("Align") {
                DSSegmentedControl(
                    selection: alignBinding(layer),
                    segments: [
                        .init(tag: 0, label: "Left"),
                        .init(tag: 1, label: "Center"),
                        .init(tag: 2, label: "Right"),
                    ]
                )
            }

            section("Position") {
                placementButtons(layer)
            }
        }
        .padding(DSSpacing.gap3)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .fill(isSelected ? DSColor.Background.neutralStronger : DSColor.Background.inset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .strokeBorder(isSelected ? DSColor.Action.primary : .clear, lineWidth: DSBorderWidth.thin)
        )
        .onTapGesture { selectedLayerID = value.id }
    }

    private func alignBinding(_ layer: Binding<BannerTextLayer>) -> Binding<Int> {
        Binding(
            get: { layer.wrappedValue.alignRaw },
            set: { layer.wrappedValue.alignRaw = $0 }
        )
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            Text(title)
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.muted)
            content()
        }
    }

    private func placementButtons(_ layer: Binding<BannerTextLayer>) -> some View {
        let current = layer.wrappedValue.y
        return HStack(spacing: DSSpacing.gap1) {
            placementButton(layer, "arrow.up.to.line", label: "Top", y: 0.18, current: current)
            placementButton(layer, "minus", label: "Middle", y: 0.5, current: current)
            placementButton(layer, "arrow.down.to.line", label: "Bottom", y: 0.82, current: current)
        }
    }

    private func placementButton(
        _ layer: Binding<BannerTextLayer>,
        _ icon: String,
        label: String,
        y: Double,
        current: Double
    ) -> some View {
        let selected = abs(current - y) < 0.01
        return Button { layer.wrappedValue.y = y } label: {
            HStack(spacing: DSSpacing.gap1) {
                Image(systemName: icon)
                    .font(.system(size: DSIconSize.xs))
                Text(label)
                    .dsTextStyle(.labelSmall)
            }
            .padding(.horizontal, DSSpacing.gap3)
            .padding(.vertical, DSSpacing.gap2)
            .foregroundStyle(selected ? DSColor.Action.primaryForeground : DSColor.Foreground.subtle)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .fill(selected ? DSColor.Action.primary : DSColor.Background.neutral)
            )
        }
        .buttonStyle(.plain)
    }

    private func weightLabel(_ raw: Int) -> String {
        Self.weights.first { $0.0 == raw }?.1 ?? "Regular"
    }

    private var fieldMenuDismiss: Binding<Bool> {
        Binding(
            get: { presentation.bannerTextFieldMenu != nil },
            set: { if !$0 { presentation.bannerTextFieldMenu = nil } }
        )
    }

    private func fieldMenuOpen(_ kind: BannerTextFieldMenu) -> Binding<Bool> {
        Binding(
            get: { presentation.bannerTextFieldMenu == kind },
            set: { presentation.bannerTextFieldMenu = $0 ? kind : nil }
        )
    }

    private func fieldMenuLabel(_ title: String) -> some View {
        HStack(spacing: DSSpacing.gap2) {
            Text(title)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: DSIconSize.xs, weight: .semibold))
                .foregroundStyle(DSColor.Foreground.muted)
        }
        .padding(.horizontal, DSSpacing.gap3)
        .padding(.vertical, DSSpacing.gap2)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                .fill(DSColor.Background.neutral)
        )
    }

    private func colorSwatch(_ layer: Binding<BannerTextLayer>) -> some View {
        let id = layer.wrappedValue.id
        let color = Color(hexRGB: layer.wrappedValue.colorHex) ?? .white
        return Button {
            pickerColor = color
            presentation.colorPicker = .bannerText(layerID: id)
        } label: {
            Circle()
                .fill(color)
                .frame(width: swatch, height: swatch)
                .overlay(Circle().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
        }
        .buttonStyle(.plain)
        .dsHoverScale()
        .help("Text color")
        .dsDropdownMenu(
            isPresented: Binding(
                get: { presentation.colorPicker == .bannerText(layerID: id) },
                set: { presentation.colorPicker = $0 ? .bannerText(layerID: id) : nil }
            ),
            anchorHeight: swatch
        ) {
            DSColorPicker(color: $pickerColor, supportsAlpha: false)
                .appliedAppearancePreference()
        }
    }

    private func addText() {
        let canvas = doc.canvasSize
        let stackIndex = BannerLayoutMetrics.nextTextStackIndex(in: texts, canvas: canvas)
        let (nx, ny) = BannerLayoutMetrics.staggeredTextPosition(stackIndex: stackIndex, canvas: canvas)
        let layer = BannerLayoutMetrics.withInitialFrame(
            BannerTextLayer(string: "Your text", fontSize: 96, colorHex: "#FFFFFF", x: nx, y: ny),
            canvas: canvas
        )
        texts.append(layer)
        selectedLayerID = layer.id
    }

    private func delete(_ id: UUID) {
        texts.removeAll { $0.id == id }
        if case .bannerText(let pickerID) = presentation.colorPicker, pickerID == id {
            presentation.colorPicker = nil
        }
        if selectedLayerID == id {
            selectedLayerID = texts.first?.id
        }
    }

    private func writeBack(_ new: [BannerTextLayer]) {
        var l = doc.layers
        l.texts = new
        doc.layers = l
    }
}
