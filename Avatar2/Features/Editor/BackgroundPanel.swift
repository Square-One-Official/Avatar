// Background-paneel (E07.1) — Notion-cover-picker-model (besluit Thierry,
// 2026-07-03): een tab-header (Gallery · Upload · Generate, "Remove" rechts)
// boven een verticaal scrollend grid met sectiekoppen en brede 16:10-tegels.
//   - Gallery: Original (als de foto bewaard is) → Color & Gradient (picker,
//     DS-kleuren, brand colors, gradient-presets) → CMS-categorieën.
//   - Upload: "+"-tegel + de persistente eigen uploads (E24.24).
//   - Generate: entrypoint naar de E42-generatie-sheet (Notion AI-equivalent).
//   - Remove: de vrijstaande cutout zonder achtergrond (E24.31-"None").
// Een keuze schrijft op het Portrait2 (kleur xor afbeelding); het canvas toont
// de achtergrond live (E07.2 doet de exportkwaliteit-compositing). Elke tegel
// toont zijn selected-state.

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

    private enum PickerTab: Hashable { case gallery, upload, generate }
    @State private var tab: PickerTab = .gallery

    @State private var brand = BrandColorKit.shared
    // E24.24: persistente custom-achtergrond-uploads (herbruikbare tegels).
    @State private var customImages = BackgroundImageKit.shared
    // E25.2: DSColorPicker vanuit de "+"-tegel in Color & Gradient.
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

    /// Brede Notion-achtige tegels: 3 kolommen, 16:10.
    private let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: DSSpacing.gap2),
        count: 3
    )
    private let tileAspect: CGFloat = 16.0 / 10.0
    /// Vaste content-hoogte zodat het paneel niet verspringt bij tab-wissel
    /// (zelfde geest als de pixelvaste breadcrumb, UXS-28).
    private let contentHeight: CGFloat = 340

    private var showsGenerateTab: Bool {
        entitlement != nil && BackgroundGenerationCatalog.hasGenerationPath
    }

    var body: some View {
        // E24-fix: in de canvas-toolbar-popover tonen we de inhoud direct
        // (zoals de Adjust-popover), niet in een tweede DSEditPanel-kaart —
        // de popover ís de kaart.
        VStack(alignment: .leading, spacing: DSSpacing.gap3) {
            header
            switch tab {
            case .gallery: galleryTab
            case .upload: uploadTab
            case .generate: generateTab
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await loadCMSBackgrounds() }
    }

    // MARK: Header — tabs links, Remove rechts (Notion-model)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: DSSpacing.gap4) {
                tabButton("Gallery", .gallery)
                tabButton("Upload", .upload)
                if showsGenerateTab { tabButton("Generate", .generate) }
                Spacer()
                Button { selectTransparent() } label: {
                    Text("Remove")
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .padding(.bottom, DSSpacing.gap2)
                }
                .buttonStyle(.plain)
                .help("Remove the background (transparent cut-out)")
            }
            Rectangle()
                .fill(DSColor.Foreground.divider)
                .frame(height: DSBorderWidth.thin)
        }
    }

    /// Tab-knop met Notion-achtige actieve underline die op de divider ligt.
    private func tabButton(_ title: String, _ value: PickerTab) -> some View {
        let isActive = tab == value
        return Button { tab = value } label: {
            Text(title)
                .dsTextStyle(.labelBase)
                .foregroundStyle(isActive ? DSColor.Foreground.primary
                                          : DSColor.Foreground.muted)
                .padding(.bottom, DSSpacing.gap2)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(isActive ? DSColor.Foreground.primary : .clear)
                        .frame(height: 2)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Gallery-tab — Original · Color & Gradient · CMS-categorieën

    private var galleryTab: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                if let original = originalImage {
                    gridSection("Original") {
                        tile(isSelected: portrait?.useOriginalBackground == true) {
                            Image(nsImage: original).resizable().scaledToFill()
                        } action: { selectOriginal() }
                        .help("Show the original photo background")
                    }
                }
                gridSection("Color & Gradient") { colorAndGradientTiles }
                if showsBanners, AppFeatureFlags.bannersEnabled, !savedBanners.isEmpty {
                    gridSection("Banners") { bannerTiles }
                }
                ForEach(cmsCategories, id: \.self) { cat in
                    gridSection(cat) { cmsTiles(for: cat) }
                }
            }
            .padding(DSSpacing.gap1)
        }
        .frame(height: contentHeight)
    }

    @ViewBuilder
    private var colorAndGradientTiles: some View {
        // E25.2: "+"-tegel opent de DSColorPicker (met eigen eyedropper); live
        // bijwerken terwijl de picker open is, bij sluiten als brand-swatch
        // bewaren.
        tile(isSelected: false) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSColor.Foreground.subtle)
        } action: {
            if let hex = portrait?.backgroundColorHex, let c = Color(hexRGB: hex) { pickerColor = c }
            showColorPicker = true
        }
        .help("Pick a colour")
        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
            DSColorPicker(color: $pickerColor, supportsAlpha: false)
                .appliedAppearancePreference()
        }
        .onChange(of: pickerColor) { _, c in
            guard showColorPicker, let hex = c.hexRGB else { return }
            selectColor(hex)
        }
        .onChange(of: showColorPicker) { _, open in
            if !open, let hex = pickerColor.hexRGB { brand.add(hex) }
        }

        ForEach(Array(BackgroundKit.colorPresets.enumerated()), id: \.offset) { _, color in
            colorTile(color)
        }
        ForEach(brand.hexColors, id: \.self) { hex in
            if let color = Color(hexRGB: hex) { colorTile(color, hex: hex) }
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

    private func colorTile(_ color: Color, hex providedHex: String? = nil) -> some View {
        let hex = providedHex ?? color.hexRGB
        let isSelected = hex != nil && portrait?.backgroundColorHex == hex
        return tile(isSelected: isSelected) {
            Rectangle().fill(color)
        } action: { if let hex { selectColor(hex) } }
    }

    private func gradientTile(_ colors: [Color]) -> some View {
        tile(isSelected: isAppliedSource(gradientKey(colors))) {
            Rectangle().fill(BackgroundKit.gradient(colors))
        } action: { selectGradient(colors) }
    }

    @ViewBuilder
    private func cmsTiles(for category: String) -> some View {
        ForEach(cmsBackgrounds.filter { $0.category == category }) { bg in
            tile(isSelected: isAppliedSource(cmsKey(bg))) {
                // E52.1: gedeelde memory/disk-cache + downsampled decode
                // i.p.v. AsyncImage (URLCache helpt niet: Supabase stuurt
                // `Cache-Control: no-cache`).
                RemoteThumbnail(url: bg.thumbnailUrl) {
                    Color(white: 0.85)
                }
            } action: { selectCMSBackground(bg) }
            .help(bg.label)
        }
    }

    // MARK: Upload-tab — "+" + persistente eigen uploads (E24.24)

    private var uploadTab: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                gridSection("Your images") {
                    tile(isSelected: false) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DSColor.Foreground.subtle)
                    } action: { uploadCustom() }
                    .help("Upload an image")

                    ForEach(customImages.imageIDs, id: \.self) { id in
                        if let image = customImages.image(for: id) {
                            tile(
                                isSelected: currentImageSignature != nil
                                    && currentImageSignature == customSignature(id)
                            ) {
                                Image(nsImage: image).resizable().scaledToFill()
                            } action: { selectCustomImage(id) }
                        }
                    }
                }
            }
            .padding(DSSpacing.gap1)
        }
        .frame(height: contentHeight)
    }

    // MARK: Generate-tab — entrypoint naar de E42-sheet (Notion AI-equivalent)

    private var generateTab: some View {
        VStack(spacing: DSSpacing.gap4) {
            Spacer()
            DSIcon(.sparkle, size: 28)
            Text("Generate a custom background with AI based on your description")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.gap6)
            GenerateBackgroundButton(
                context: .portrait,
                entitlement: entitlement,
                onSaved: { data in
                    // Bewaren als herbruikbare upload-tegel + meteen toepassen.
                    let stored = customImages.add(data) ?? data
                    apply(.image(stored))
                }
            )
            .padding(.horizontal, DSSpacing.gap8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: contentHeight)
    }

    // MARK: Grid-bouwstenen

    @ViewBuilder
    private func gridSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            Text(title)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
            LazyVGrid(columns: gridColumns, spacing: DSSpacing.gap2) {
                content()
            }
        }
    }

    /// Gedeelde brede tegel (16:10, Notion-model) met een consistente
    /// 2pt selected-rand voor alle bronnen (kleur, gradient, CMS, upload).
    private func tile(
        isSelected: Bool,
        @ViewBuilder content: () -> some View, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .fill(DSColor.Background.neutral)
                .aspectRatio(tileAspect, contentMode: .fit)
                .overlay { content() }
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .strokeBorder(DSColor.Foreground.primary, lineWidth: isSelected ? 2 : 0)
                }
        }
        .buttonStyle(.plain)
        .dsHoverScale()
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

    // MARK: CMS-data

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
            // tegels vullen terwijl het paneel opent; her-opens zijn instant.
            ThumbnailCache.shared.prefetch(fetched.map(\.thumbnailUrl))
        }
        let config = (try? await configFetch) ?? .empty
        if !config.gradientPresets.isEmpty {
            BackgroundPanel.gradientCache = config.gradientPresets
            cmsGradients = config.gradientPresets
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

    // MARK: Banners (E40.1/E40.2) — een gemaakte banner als portret-achtergrond

    private var originalImage: NSImage? {
        guard let data = portrait?.originalData else { return nil }
        return NSImage(data: data)
    }

    @ViewBuilder
    private var bannerTiles: some View {
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
                tile(isSelected: isCurrent) {
                    Image(nsImage: img).resizable().scaledToFill()
                        .overlay(alignment: .topTrailing) {
                            if isStale { updateBadge }
                        }
                } action: { applyBanner(doc) }
                .help(isStale
                      ? "This banner changed — click to update the background"
                      : (doc.name.isEmpty ? "Untitled banner" : doc.name))
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

    /// E24.31: terug naar de vrijstaande cutout zonder achtergrond ("Remove").
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
        // E24.24: persistent opslaan als herbruikbare tegel (+ downscale, 24.23);
        // de teruggegeven PNG wordt meteen de achtergrond.
        let stored = customImages.add(data) ?? data
        apply(.image(stored))
    }

    /// E24.24: kies een eerder geüploade (persistente) achtergrond-tegel.
    private func selectCustomImage(_ id: String) {
        guard let data = customImages.data(for: id) else { return }
        apply(.image(data))
    }

}
