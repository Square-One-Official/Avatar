// Background-paneel (E07.1, Figma App / Choose Background 4017:1099).
// UX-audit 2026-07: bovenaan een gelabelde modus-rij (Original / None, met
// checkerboard voor transparant), daaronder "Image" (upload + eigen uploads +
// gradient-presets, 56pt-tegels) met een op-zichzelf-staande "Generate
// background"-knop, dan de CMS-categorieën en "Color" (36pt-rondjes + brand
// colors + DSColorPicker). Een keuze schrijft op het Portrait2 (kleur xor
// afbeelding); het canvas toont de achtergrond live (E07.2 doet de
// exportkwaliteit-compositing). Elke kiesbare tegel toont zijn selected-state.

import AppKit
import AvatarKit
import AvatarUI
import SwiftData
import SwiftUI

struct BackgroundPanel: View {
    let portrait: Portrait2?
    /// E31.7: optionele apply-target. Default schrijft op `portrait` (single
    /// editor + board single-select). De board-batch geeft hier een closure die
    /// de keuze op ALLE geselecteerde portretten toepast. De UI is identiek;
    /// `portrait` blijft de bron voor display/selectie-state (Original/custom).
    var onApply: ((PortraitBackground) -> Void)? = nil
    /// Benodigd voor de CMS-achtergronden-fetch; optioneel zodat bestaande
    /// aanroeplocaties zonder entitlement blijven werken.
    var entitlement: EntitlementModel? = nil
    /// UX-audit: banners-als-achtergrond (E40) is een matched-background-
    /// concept (Social Preview), geen generieke achtergrond-keuze. De sectie
    /// verschijnt alleen als de aanroeper er expliciet om vraagt — de portret-
    /// editor en het board doen dat niet.
    var showsBanners: Bool = false

    @State private var brand = BrandColorKit.shared
    // E24.24: persistente custom-achtergrond-uploads (herbruikbare swatches).
    @State private var customImages = BackgroundImageKit.shared
    // E25.2: DSColorPicker vanuit de "+"-knop in de Color-rij.
    @State private var showColorPicker = false
    @State private var pickerColor: Color = .white
    // CMS-achtergronden (E33+). Sessie-cache zodat herhaalbaar openen
    // geen flits geeft; leeg = nog niet geladen (geen fallback nodig).
    @State private var cmsBackgrounds: [RemoteBackground] = BackgroundPanel.sessionCache
    // CMS-gradient-presets (E33+). Leeg = fallback op BackgroundKit.gradientPresets.
    @State private var cmsGradients: [RemoteGradientPreset] = BackgroundPanel.gradientCache
    // E40.1: gemaakte banners als achtergrond-bron (BannerDoc-previews).
    @Query(sort: \BannerDoc.updatedAt, order: .reverse) private var bannerDocs: [BannerDoc]
    private var savedBanners: [BannerDoc] { bannerDocs.filter { $0.previewImageData != nil } }

    private static var sessionCache: [RemoteBackground] = []
    private static var gradientCache: [RemoteGradientPreset] = []

    // UX-audit: welke bron (gradient/CMS) de huidige `.image`-bytes leverde,
    // vastgelegd op apply-moment (bron-key → content-signature). Nodig omdat
    // een CMS-keuze de vólle resolutie toepast (≠ thumbnail-bytes) en een
    // gradient pas bij keuze gerenderd wordt. Sessie-scope: na een herstart is
    // alleen deze highlight kwijt, de achtergrond zelf niet.
    private static var appliedSourceSignatures: [String: Int] = [:]
    // Custom uploads zijn wél persistent vergelijkbaar: signature van de
    // opgeslagen PNG, één keer per id berekend (scheelt disk-reads per render).
    private static var customImageSignatures: [String: Int] = [:]

    /// Beeld-tegels (Original/None, uploads, gradients, CMS): groot genoeg om
    /// de inhoud te beoordelen. Kleuren blijven 36 — het maatverschil
    /// communiceert meteen het type.
    private let imageTile: CGFloat = 56
    private let colorSwatch: CGFloat = 36

    var body: some View {
        // E24-fix: in de canvas-toolbar-popover tonen we de inhoud direct
        // (zoals de Adjust-popover), niet in een tweede DSEditPanel-kaart —
        // de popover ís de kaart. Rijen scrollen met rand-inset + fade.
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            // Modus-rij zonder sectiekop: de tegels dragen hun eigen label
            // (Original / None) — een kop "Background" ín het Background-
            // paneel voegde niets toe.
            backgroundModeRow
            section("Image") { imageSection }
            if showsBanners, AppFeatureFlags.bannersEnabled, !savedBanners.isEmpty {
                section("Banners") { bannersRow }
            }
            ForEach(cmsCategories, id: \.self) { cat in
                section(cat) { cmsRow(for: cat) }
            }
            section("Color") { colorRow }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await loadCMSBackgrounds() }
    }

    private var cmsCategories: [String] {
        var seen = Set<String>()
        return cmsBackgrounds.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    private func loadCMSBackgrounds() async {
        guard let backend = entitlement?.backend else { return }
        async let bgFetch = backend.backgrounds()
        async let configFetch = backend.appConfig()
        let fetched = (try? await bgFetch) ?? []
        if !fetched.isEmpty {
            BackgroundPanel.sessionCache = fetched
            cmsBackgrounds = fetched
            // E52.1: warm de gedeelde thumbnail-cache (memory + disk) zodat de
            // swatches vullen terwijl het paneel opent; her-opens zijn instant.
            ThumbnailCache.shared.prefetch(fetched.map(\.thumbnailUrl))
        }
        let config = (try? await configFetch) ?? .empty
        if !config.gradientPresets.isEmpty {
            BackgroundPanel.gradientCache = config.gradientPresets
            cmsGradients = config.gradientPresets
        }
    }

    // MARK: Selectie-state

    /// Content-signature van de huidige `.image`-achtergrond (nil bij een
    /// andere modus). FNV over ~256 verspreide bytes — goedkoop per render.
    private var currentImageSignature: Int? {
        portrait?.backgroundImageData.map(Portrait2.cutoutSignature)
    }

    /// Is de bron met deze key (gradient/CMS) de huidige achtergrond?
    private func isAppliedSource(_ key: String) -> Bool {
        guard let sig = currentImageSignature else { return false }
        return Self.appliedSourceSignatures[key] == sig
    }

    private func recordAppliedSource(_ key: String, data: Data) {
        Self.appliedSourceSignatures[key] = Portrait2.cutoutSignature(data)
    }

    private func customSignature(_ id: String) -> Int? {
        if let cached = Self.customImageSignatures[id] { return cached }
        guard let data = customImages.data(for: id) else { return nil }
        let sig = Portrait2.cutoutSignature(data)
        Self.customImageSignatures[id] = sig
        return sig
    }

    private func gradientKey(_ colors: [Color]) -> String {
        "gradient:" + colors.compactMap(\.hexRGB).joined(separator: "-")
    }

    private func cmsKey(_ bg: RemoteBackground) -> String {
        "cms:" + bg.imageUrl.absoluteString
    }

    // MARK: CMS-rijen

    @ViewBuilder
    private func cmsRow(for category: String) -> some View {
        scrollRow {
            ForEach(cmsBackgrounds.filter { $0.category == category }) { bg in
                Button { selectCMSBackground(bg) } label: {
                    imageTileSurface(isSelected: isAppliedSource(cmsKey(bg))) {
                        // E52.1: gedeelde memory/disk-cache + downsampled
                        // decode i.p.v. AsyncImage (URLCache helpt niet:
                        // Supabase stuurt `Cache-Control: no-cache`).
                        RemoteThumbnail(url: bg.thumbnailUrl) {
                            Color(white: 0.85)
                        }
                    }
                }
                .buttonStyle(.plain)
                .dsHoverScale()
                .help(bg.label)
            }
        }
    }

    private func selectCMSBackground(_ bg: RemoteBackground) {
        // E52.1: het paneel toont alleen nog de verkleinde thumbnail-variant;
        // het volle origineel wordt pas bij daadwerkelijk toepassen opgehaald
        // (export-compositing verdient de volledige resolutie).
        Task {
            guard let png = try? await URLSession.shared.data(from: bg.imageUrl).0 else { return }
            await MainActor.run {
                recordAppliedSource(cmsKey(bg), data: png)
                apply(.image(png))
            }
        }
    }

    // MARK: Background-modus — Original + None (E24.31, UX-audit: gelabeld)

    private var originalImage: NSImage? {
        guard let data = portrait?.originalData else { return nil }
        return NSImage(data: data)
    }

    /// Transparant geselecteerd = cutout zonder achtergrond (geen Original,
    /// geen kleur/afbeelding).
    private var isTransparentSelected: Bool {
        guard let portrait else { return false }
        return !portrait.useOriginalBackground
            && portrait.backgroundColorHex == nil
            && portrait.backgroundImageData == nil
    }

    private var backgroundModeRow: some View {
        HStack(alignment: .top, spacing: DSSpacing.gap2) {
            // "Original" — alleen als de originele foto bewaard is.
            if let original = originalImage {
                modeTile("Original",
                         isSelected: portrait?.useOriginalBackground == true,
                         help: "Show the original photo background") {
                    Image(nsImage: original).resizable().scaledToFill()
                } action: { selectOriginal() }
            }
            // "None" — de vrijstaande cutout (default). Checkerboard is dé
            // transparantie-conventie (Photoshop/Figma/PNG-preview).
            modeTile("None", isSelected: isTransparentSelected,
                     help: "No background (transparent cut-out)") {
                TransparencyCheckerboard()
            } action: { selectTransparent() }
        }
        .padding(.vertical, DSSpacing.gap2)
        .padding(.leading, DSSpacing.gap1)
    }

    private func modeTile(
        _ label: String, isSelected: Bool, help: String,
        @ViewBuilder content: () -> some View, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: DSSpacing.gap1) {
                imageTileSurface(isSelected: isSelected) { content() }
                Text(label)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(isSelected ? DSColor.Foreground.primary
                                                : DSColor.Foreground.muted)
            }
        }
        .buttonStyle(.plain)
        .dsHoverScale()
        .help(help)
    }

    /// Gedeeld tegel-oppervlak voor alle beeld-bronnen: afgeronde tegel met
    /// een consistente 2pt selected-rand (zelfde taal als de kleur-rondjes).
    private func imageTileSurface(
        isSelected: Bool, @ViewBuilder content: () -> some View
    ) -> some View {
        RoundedRectangle(cornerRadius: DSRadius.lg)
            .fill(DSColor.Background.neutral)
            .frame(width: imageTile, height: imageTile)
            .overlay { content() }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .strokeBorder(DSColor.Foreground.primary, lineWidth: isSelected ? 2 : 0)
            }
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
                .scrollRowTrailingInset()
        }
        // Gedeeld met de andere editor-panelen (zie ScrollRowEdgeFade).
        .horizontalScrollEdgeFade()
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

    // MARK: Image-sectie — upload + eigen uploads + gradients + generate-knop

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            imageRow
            // UX-audit: generate is een actie (kost een sheet/credits), geen
            // kiesbare swatch — dus een gelabelde knop los onder de rij.
            GenerateBackgroundButton(
                context: .portrait,
                entitlement: entitlement,
                onSaved: { data in
                    let stored = customImages.add(data) ?? data
                    apply(.image(stored))
                }
            )
            .padding(.horizontal, DSSpacing.gap1)
        }
    }

    private var imageRow: some View {
        scrollRow {
            Button(action: uploadCustom) {
                imageTileSurface(isSelected: false) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
            }
            .buttonStyle(.plain)
            .dsHoverScale()
            .help("Upload an image")

            // E24.24: persistente custom-uploads als herbruikbare swatches.
            ForEach(customImages.imageIDs, id: \.self) { id in
                if let image = customImages.image(for: id) {
                    Button { selectCustomImage(id) } label: {
                        imageTileSurface(
                            isSelected: currentImageSignature != nil
                                && currentImageSignature == customSignature(id)
                        ) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .buttonStyle(.plain)
                    .dsHoverScale()
                }
            }

            // Gradient-presets: CMS-gestuurd als aanwezig, anders hardgecodeerde fallback.
            if cmsGradients.isEmpty {
                ForEach(Array(BackgroundKit.gradientPresets.enumerated()), id: \.offset) { _, colors in
                    gradientTile(colors)
                }
            } else {
                ForEach(cmsGradients, id: \.label) { g in
                    if let from = Color(hexRGB: g.fromHex), let to = Color(hexRGB: g.toHex) {
                        gradientTile([from, to])
                    }
                }
            }
        }
    }

    private func gradientTile(_ colors: [Color]) -> some View {
        Button { selectGradient(colors) } label: {
            imageTileSurface(isSelected: isAppliedSource(gradientKey(colors))) {
                Rectangle().fill(BackgroundKit.gradient(colors))
            }
        }
        .buttonStyle(.plain)
        .dsHoverScale()
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
                    .frame(width: colorSwatch, height: colorSwatch)
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
                colorSwatchView(color)
            }
            ForEach(brand.hexColors, id: \.self) { hex in
                if let color = Color(hexRGB: hex) { colorSwatchView(color, hex: hex) }
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

    private func colorSwatchView(_ color: Color, hex providedHex: String? = nil) -> some View {
        let hex = providedHex ?? color.hexRGB
        let isSelected = hex != nil && portrait?.backgroundColorHex == hex
        return Button { if let hex { selectColor(hex) } } label: {
            Circle()
                .fill(color)
                .frame(width: colorSwatch, height: colorSwatch)
                .overlay {
                    Circle().strokeBorder(DSColor.Foreground.primary,
                                          lineWidth: isSelected ? 2 : 0)
                }
        }
        .buttonStyle(.plain)
        .dsHoverScale()
    }

    // MARK: Banners-rij (E40.1/E40.2) — een gemaakte banner als portret-achtergrond

    private var bannersRow: some View {
        scrollRow {
            ForEach(savedBanners) { doc in
                if let data = doc.previewImageData, let img = NSImage(data: data) {
                    // Gekoppeld = dit portret nam z'n achtergrond van déze banner
                    // (E40.2). Stale = de banner is sindsdien in de Studio gewijzigd
                    // (opgeslagen bytes ≠ huidige preview) → "Update background".
                    // Vergelijk via BannerDeletion.isLinked (gedecodeerde
                    // PersistentIdentifier) — de encoded sleutel-string zelf is
                    // niet byte-stabiel (E46-les), dus nooit string == string.
                    let linked = BannerDeletion.isLinked(portrait?.backgroundBannerID, to: doc)
                    let isCurrent = linked || portrait?.backgroundImageData == data
                    let isStale = linked && portrait?.backgroundImageData != data
                    Button { applyBanner(doc) } label: {
                        RoundedRectangle(cornerRadius: DSRadius.lg)
                            .fill(DSColor.Background.neutral)
                            .frame(width: imageTile * 3, height: imageTile)
                            .overlay { Image(nsImage: img).resizable().scaledToFill() }
                            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                            .overlay(
                                RoundedRectangle(cornerRadius: DSRadius.lg)
                                    .strokeBorder(
                                        isCurrent ? DSColor.Foreground.primary : .clear,
                                        lineWidth: isCurrent ? 2 : 0
                                    )
                            )
                            .overlay(alignment: .topTrailing) {
                                if isStale { updateBadge }
                            }
                    }
                    .buttonStyle(.plain)
                    .dsHoverScale()
                    .help(isStale
                          ? "This banner changed — click to update the background"
                          : (doc.name.isEmpty ? "Untitled banner" : doc.name))
                }
            }
        }
    }

    /// E40.2: subtiel "Update"-vaantje op een gekoppelde-maar-verouderde banner.
    private var updateBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text("Update")
        }
        .dsTextStyle(.labelSmall)
        .foregroundStyle(.white)
        .padding(.horizontal, DSSpacing.gap1)
        .padding(.vertical, 1)
        .background(DSColor.Action.primary, in: Capsule())
        .padding(DSSpacing.gap1)
    }

    /// Past de huidige banner-preview toe als achtergrond én legt de E40.2-
    /// koppeling vast (alleen in de enkel-portret-editor, niet in de board-batch).
    private func applyBanner(_ doc: BannerDoc) {
        guard let data = doc.previewImageData else { return }
        apply(.image(data))
        if onApply == nil { portrait?.backgroundBannerID = BannerDeletion.linkKey(for: doc) }
    }

    // MARK: Acties

    /// E31.7: één apply-punt — naar de injected closure (batch) of het portret.
    private func apply(_ background: PortraitBackground) {
        if let onApply { onApply(background) } else { portrait?.setBackground(background) }
    }

    /// E24.31: toon de originele foto vol (omkeerbaar).
    private func selectOriginal() {
        guard portrait?.originalData != nil else { return }
        apply(.original)
    }

    /// E24.31: terug naar de vrijstaande cutout zonder achtergrond.
    private func selectTransparent() {
        apply(.transparent)
    }

    private func selectColor(_ hex: String) {
        apply(.color(hex))
    }

    private func selectGradient(_ colors: [Color]) {
        guard let png = BackgroundKit.renderGradientPNG(colors) else { return }
        recordAppliedSource(gradientKey(colors), data: png)
        apply(.image(png))
    }

    private func uploadCustom() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        // E24.24: persistent opslaan als herbruikbare swatch (+ downscale, 24.23);
        // de teruggegeven PNG wordt meteen de achtergrond.
        let stored = customImages.add(data) ?? data
        apply(.image(stored))
    }

    /// E24.24: kies een eerder geüploade (persistente) achtergrond-swatch.
    private func selectCustomImage(_ id: String) {
        guard let data = customImages.data(for: id) else { return }
        apply(.image(data))
    }

}

/// Dambord-vlak voor de "None"-tegel — de universele transparantie-conventie
/// (Photoshop/Figma/PNG-preview) i.p.v. het eerdere `circle.dotted`-icoon.
private struct TransparencyCheckerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 7
            var y: CGFloat = 0, row = 0
            while y < size.height {
                var x: CGFloat = 0, col = 0
                while x < size.width {
                    if (row + col) % 2 == 0 {
                        ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)),
                                 with: .color(.gray.opacity(0.35)))
                    }
                    x += s; col += 1
                }
                y += s; row += 1
            }
        }
    }
}
