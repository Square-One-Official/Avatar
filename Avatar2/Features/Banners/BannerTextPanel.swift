// E37.4 — Text-paneel van de Banner Studio. Voegt tekstlagen toe en bewerkt ze:
// inhoud, grootte, gewicht, kleur en verticale plaatsing.
//
// Velden binden op een LOKALE werk-kopie (`@State texts`) i.p.v. rechtstreeks op
// `doc.layers` — anders her-encodeerde elke toetsaanslag de hele laag-stack +
// `touch()`, wat de hele Studio (incl. dit TextField) midden in het typen
// herbouwde: cursor sprong, tekens vielen weg ("paneel doet het niet"). De
// werk-kopie maakt typen vloeiend; `onChange` schrijft terug naar `doc.layers`
// (→ `touch()` → live canvas-render via CoreText `CTLine` in `BannerDocRenderer`).
// Font-familie + letter-/regelafstand + meerregelige uitlijning volgen wanneer
// het canvas laag-sleep + meerregelige render krijgt.

import AppKit
import AvatarUI
import SwiftUI

struct BannerTextPanel: View {
    @Bindable var doc: BannerDoc

    /// Lokale werk-kopie van de tekstlagen; TextFields/sliders binden hierop zodat
    /// typen vloeiend is. `onChange` synct terug naar `doc.layers`.
    @State private var texts: [BannerTextLayer] = []
    @State private var didLoad = false

    private static let weights: [(Int, String)] = [(0, "Regular"), (1, "Medium"), (2, "Semibold"), (3, "Bold")]

    var body: some View {
        DSEditPanel(title: "Text") {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                DSNeutralButton("Add text") { addText() }

                if texts.isEmpty {
                    Text("No text yet — add a line to start.")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                } else {
                    ForEach($texts) { $layer in
                        layerCard($layer)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Eén keer hydrateren uit de doc; daarna is de werk-kopie de bron terwijl
        // het paneel open is (de enige mutator in de editor).
        .onAppear {
            if !didLoad { texts = doc.layers.texts; didLoad = true }
        }
        // Live terugschrijven → canvas her-rendert; lokale state houdt het typen glad.
        .onChange(of: texts) { _, new in writeBack(new) }
    }

    // MARK: Layer-kaart

    @ViewBuilder private func layerCard(_ layer: Binding<BannerTextLayer>) -> some View {
        let value = layer.wrappedValue
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            HStack(spacing: DSSpacing.gap2) {
                TextField("Text", text: layer.string)
                    .textFieldStyle(.plain)
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(DSColor.Foreground.primary)
                DSColorPicker(color: colorBinding(layer), supportsAlpha: false)
                    .frame(width: 26, height: 26)
                Button { delete(value.id) } label: {
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
                    Slider(value: layer.fontSize, in: 24...240)
                        .frame(width: 96)
                }
                // Gewicht
                Menu {
                    ForEach(Self.weights, id: \.0) { w in
                        Button(w.1) { layer.wrappedValue.weightRaw = w.0 }
                    }
                } label: {
                    Text(weightLabel(value.weightRaw)).dsTextStyle(.labelSmall)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer(minLength: 0)

                // Verticale plaatsing
                placementButtons(layer)
            }
        }
        .padding(DSSpacing.gap3)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .fill(DSColor.Background.inset)
        )
    }

    private func placementButtons(_ layer: Binding<BannerTextLayer>) -> some View {
        let current = layer.wrappedValue.y
        return HStack(spacing: 2) {
            placementButton(layer, "arrow.up.to.line", y: 0.18, current: current)
            placementButton(layer, "minus", y: 0.5, current: current)
            placementButton(layer, "arrow.down.to.line", y: 0.82, current: current)
        }
    }

    private func placementButton(_ layer: Binding<BannerTextLayer>, _ icon: String, y: Double, current: Double) -> some View {
        let selected = abs(current - y) < 0.01
        return Button { layer.wrappedValue.y = y } label: {
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

    // MARK: Mutaties (op de lokale werk-kopie; onChange synct naar de doc)

    private func addText() {
        texts.append(BannerTextLayer(string: "Your text", fontSize: 96, colorHex: "#FFFFFF", x: 0.5, y: 0.5))
    }

    private func delete(_ id: UUID) {
        texts.removeAll { $0.id == id }
    }

    private func writeBack(_ new: [BannerTextLayer]) {
        var l = doc.layers
        l.texts = new
        doc.layers = l
    }

    private func colorBinding(_ layer: Binding<BannerTextLayer>) -> Binding<Color> {
        Binding(
            get: { Color(hexRGB: layer.wrappedValue.colorHex) ?? .white },
            set: { layer.wrappedValue.colorHex = $0.hexRGB ?? "#FFFFFF" }
        )
    }
}
