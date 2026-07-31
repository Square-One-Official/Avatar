// E38.3 + E38.4 + E37.7 — Shaders-paneel van de Banner Studio. Voegt procedurale
// effecten toe (catalogus uit `ShaderCatalog`), stapelt ze (volgorde = render-
// z-volgorde), en bewerkt per laag de params met DS-sliders + aan/uit + verwijder
// + herorden (omhoog/omlaag). Mutaties lopen op een LOKALE werk-kopie (zoals het
// text-paneel) zodat sliders vloeiend zijn; `onChange` schrijft terug naar
// `doc.layers.shaders` → `touch()` → de canvas bakt de stack live mee (E38.2).

import AvatarUI
import SwiftUI

struct BannerShaderPanel: View {
    @Bindable var doc: BannerDoc
    var subtitle: String?

    /// Lokale werk-kopie van de shader-stack; UI bindt hierop, `onChange` synct.
    @State private var layers: [BannerShaderLayer] = []
    @State private var didLoad = false

    var body: some View {
        DSEditPanel(title: "Effects", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                Text("Add effect")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.gap2) {
                        ForEach(ShaderCatalog.all) { effect in
                            Button { add(effect) } label: { effectChip(effect) }
                                .buttonStyle(.plain)
                                .dsHoverScale()
                                .help("Add \(effect.displayName)")
                        }
                    }
                    .padding(.vertical, DSSpacing.gap2)
                    .padding(.leading, DSSpacing.gap1)
                    .scrollRowTrailingInset()
                }
                .horizontalScrollEdgeFade()

                if layers.isEmpty {
                    Text("No effects yet — add one above. Applied to the whole banner.")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array($layers.enumerated()), id: \.element.id) { index, $layer in
                        layerCard($layer, index: index)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if !didLoad { layers = doc.layers.shaders; didLoad = true } }
        .onChange(of: layers) { _, new in writeBack(new) }
    }

    // MARK: Catalogus-chip

    private func effectChip(_ effect: ShaderEffect) -> some View {
        VStack(spacing: DSSpacing.gap1) {
            // Live preview-thumbnail: het staal mét déze shader (default-params)
            // erop — zo zie je het effect vóór toevoegen (E38.3-follow-up).
            Self.sampleSwatch
                .frame(width: 56, height: 36)
                .bannerShaders([effect.makeLayer()])
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                        .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
                )
            Text(effect.displayName)
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.subtle)
                .lineLimit(1)
        }
        .frame(width: 64)
    }

    /// Representatief mini-staal (gradient + vormen) zodat élke shader — óók de
    /// distortions/halftone, die structuur nodig hebben — zichtbaar verschilt in
    /// z'n live-preview-thumbnail.
    @ViewBuilder private static var sampleSwatch: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.30, green: 0.55, blue: 1.00),
                         Color(red: 0.65, green: 0.40, blue: 0.95),
                         Color(red: 1.00, green: 0.55, blue: 0.65)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(.white.opacity(0.55)).frame(width: 14).offset(x: -11, y: -5)
            Capsule().fill(.white.opacity(0.85)).frame(width: 26, height: 4).offset(y: 8)
        }
    }

    // MARK: Layer-kaart

    @ViewBuilder private func layerCard(_ layer: Binding<BannerShaderLayer>, index: Int) -> some View {
        let value = layer.wrappedValue
        let effect = ShaderCatalog.effect(for: value.key)
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: value.enabled ? "eye" : "eye.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(DSColor.Foreground.muted)
                    .onTapGesture { layer.wrappedValue.enabled.toggle() }
                    .help(value.enabled ? "Hide" : "Show")

                Text(effect?.displayName ?? value.key)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)

                Spacer(minLength: 0)

                Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.plain).disabled(index == 0)
                    .foregroundStyle(index == 0 ? DSColor.Foreground.divider : DSColor.Foreground.muted)
                    .help("Move up")
                Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(.plain).disabled(index >= layers.count - 1)
                    .foregroundStyle(index >= layers.count - 1 ? DSColor.Foreground.divider : DSColor.Foreground.muted)
                    .help("Move down")
                Button { delete(value.id) } label: {
                    Image(systemName: "trash").foregroundStyle(DSColor.Foreground.muted)
                }
                .buttonStyle(.plain).help("Remove")
            }
            .font(.system(size: 13))

            if let effect, value.enabled {
                ForEach(effect.params) { p in
                    HStack(spacing: DSSpacing.gap2) {
                        Text(p.label)
                            .dsTextStyle(.labelSmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                            .frame(width: 64, alignment: .leading)
                        DSSlider(value: paramBinding(layer, p), in: p.range)
                    }
                }
            }
        }
        .padding(DSSpacing.gap3)
        .background(
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .fill(DSColor.Background.inset)
        )
        .opacity(value.enabled ? 1 : 0.55)
    }

    // MARK: Mutaties (lokale werk-kopie; onChange synct naar de doc)

    private func add(_ effect: ShaderEffect) {
        layers.append(effect.makeLayer())
    }

    private func delete(_ id: UUID) {
        layers.removeAll { $0.id == id }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard layers.indices.contains(index), layers.indices.contains(target) else { return }
        layers.swapAt(index, target)
    }

    private func writeBack(_ new: [BannerShaderLayer]) {
        var l = doc.layers
        l.shaders = new
        doc.layers = l
    }

    private func paramBinding(_ layer: Binding<BannerShaderLayer>, _ p: ShaderParam) -> Binding<Double> {
        Binding(
            get: { layer.wrappedValue.params[p.key] ?? p.defaultValue },
            set: { layer.wrappedValue.params[p.key] = $0 }
        )
    }
}
