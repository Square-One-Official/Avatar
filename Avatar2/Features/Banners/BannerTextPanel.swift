// E37.4 — Text-paneel van de Banner Studio. Voegt tekstlagen toe en bewerkt ze:
// inhoud, grootte, gewicht, kleur en verticale plaatsing. Mutaties lopen via
// `BannerDoc.layers.texts` → `touch()` → de Studio-canvas her-rendert (CoreText
// `CTLine` in `BannerDocRenderer`). Font-familie + letter-/regelafstand +
// meerregelige uitlijning volgen wanneer de canvas laag-sleep + meerregelige
// render krijgt (zie 37.4-follow-up in de Result).

import AppKit
import AvatarUI
import SwiftUI

struct BannerTextPanel: View {
    @Bindable var doc: BannerDoc

    private static let weights: [(Int, String)] = [(0, "Regular"), (1, "Medium"), (2, "Semibold"), (3, "Bold")]

    var body: some View {
        DSEditPanel(title: "Text") {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                DSNeutralButton("Add text") { addText() }

                if doc.layers.texts.isEmpty {
                    Text("No text yet — add a line to start.")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                } else {
                    ForEach(Array(doc.layers.texts.enumerated()), id: \.element.id) { index, _ in
                        layerCard(index)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Layer-kaart

    @ViewBuilder private func layerCard(_ i: Int) -> some View {
        guard i < doc.layers.texts.count else { return AnyView(EmptyView()) }
        let layer = doc.layers.texts[i]
        return AnyView(
            VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                HStack(spacing: DSSpacing.gap2) {
                    TextField("Text", text: stringBinding(i))
                        .textFieldStyle(.plain)
                        .dsTextStyle(.bodyMedium)
                        .foregroundStyle(DSColor.Foreground.primary)
                    DSColorPicker(color: colorBinding(i), supportsAlpha: false)
                        .frame(width: 26, height: 26)
                    Button { delete(i) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(DSColor.Foreground.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Delete text")
                }

                HStack(spacing: DSSpacing.gap3) {
                    // Grootte
                    HStack(spacing: DSSpacing.gap1) {
                        Image(systemName: "textformat.size").font(.system(size: 11)).foregroundStyle(DSColor.Foreground.muted)
                        Slider(value: sizeBinding(i), in: 24...240)
                            .frame(width: 96)
                    }
                    // Gewicht
                    Menu {
                        ForEach(Self.weights, id: \.0) { w in
                            Button(w.1) { setText(i) { $0.weightRaw = w.0 } }
                        }
                    } label: {
                        Text(weightLabel(layer.weightRaw)).dsTextStyle(.labelSmall)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer(minLength: 0)

                    // Verticale plaatsing
                    placementButtons(i, current: layer.y)
                }
            }
            .padding(DSSpacing.gap3)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    .fill(DSColor.Background.inset)
            )
        )
    }

    private func placementButtons(_ i: Int, current: Double) -> some View {
        HStack(spacing: 2) {
            placementButton(i, "arrow.up.to.line", y: 0.18, current: current)
            placementButton(i, "minus", y: 0.5, current: current)
            placementButton(i, "arrow.down.to.line", y: 0.82, current: current)
        }
    }

    private func placementButton(_ i: Int, _ icon: String, y: Double, current: Double) -> some View {
        let selected = abs(current - y) < 0.01
        return Button { setText(i) { $0.y = y } } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 22, height: 22)
                .foregroundStyle(selected ? DSColor.Action.primaryForeground : DSColor.Foreground.subtle)
                .background(
                    RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous)
                        .fill(selected ? DSColor.Action.primary : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func weightLabel(_ raw: Int) -> String {
        Self.weights.first { $0.0 == raw }?.1 ?? "Regular"
    }

    // MARK: Mutaties

    private func addText() {
        var l = doc.layers
        l.texts.append(BannerTextLayer(string: "Your text", fontSize: 96, colorHex: "#FFFFFF", x: 0.5, y: 0.5))
        doc.layers = l
    }

    private func delete(_ i: Int) {
        var l = doc.layers
        guard i < l.texts.count else { return }
        l.texts.remove(at: i)
        doc.layers = l
    }

    private func setText(_ i: Int, _ mutate: (inout BannerTextLayer) -> Void) {
        var l = doc.layers
        guard i < l.texts.count else { return }
        mutate(&l.texts[i])
        doc.layers = l
    }

    private func stringBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < doc.layers.texts.count ? doc.layers.texts[i].string : "" },
            set: { newValue in setText(i) { $0.string = newValue } }
        )
    }

    private func sizeBinding(_ i: Int) -> Binding<Double> {
        Binding(
            get: { i < doc.layers.texts.count ? doc.layers.texts[i].fontSize : 96 },
            set: { newValue in setText(i) { $0.fontSize = newValue } }
        )
    }

    private func colorBinding(_ i: Int) -> Binding<Color> {
        Binding(
            get: { i < doc.layers.texts.count ? (Color(hexRGB: doc.layers.texts[i].colorHex) ?? .white) : .white },
            set: { newColor in setText(i) { $0.colorHex = newColor.hexRGB ?? "#FFFFFF" } }
        )
    }
}
