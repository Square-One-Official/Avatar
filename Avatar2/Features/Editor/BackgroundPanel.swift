// Background-paneel (E07.1, Figma App / Choose Background 4017:1099).
// Twee secties: "Image" (+ custom upload, gegenereerde gradient-presets)
// en "Color" (DS-projectkleur-presets + persistente brand colors + een
// eyedropper). Een keuze schrijft op het Portrait2 (kleur xor afbeelding);
// het canvas toont de achtergrond live (E07.2 doet de exportkwaliteit-
// compositing). Tegelijk gaat het dot-grid uit.

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
    private static let imageCache = NSCache<NSURL, NSImage>()

    private let swatch: CGFloat = 36

    var body: some View {
        // E24-fix: in de canvas-toolbar-popover tonen we de inhoud direct
        // (zoals de Adjust-popover), niet in een tweede DSEditPanel-kaart —
        // de popover ís de kaart. Rijen scrollen met rand-inset + fade.
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            section("Background") { backgroundModeRow }
            section("Image") { imageRow }
            // E40: een gemaakte banner als achtergrond — achter de feature-flag
            // (release zonder banners).
            if AppFeatureFlags.bannersEnabled, !savedBanners.isEmpty {
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
            prefetchThumbnails(for: fetched)
        }
        let config = (try? await configFetch) ?? .empty
        if !config.gradientPresets.isEmpty {
            BackgroundPanel.gradientCache = config.gradientPresets
            cmsGradients = config.gradientPresets
        }
    }

    private func prefetchThumbnails(for items: [RemoteBackground]) {
        let urls = items.map(\.thumbnailUrl)
            .filter { BackgroundPanel.imageCache.object(forKey: $0 as NSURL) == nil }
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask {
                        guard let (data, _) = try? await URLSession.shared.data(from: url),
                              let image = NSImage(data: data) else { return }
                        BackgroundPanel.imageCache.setObject(image, forKey: url as NSURL)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cmsRow(for category: String) -> some View {
        scrollRow {
            ForEach(cmsBackgrounds.filter { $0.category == category }) { bg in
                Button { selectCMSBackground(bg) } label: {
                    let cached = BackgroundPanel.imageCache.object(forKey: bg.thumbnailUrl as NSURL)
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .fill(DSColor.Background.neutral)
                        .frame(width: swatch, height: swatch)
                        .overlay {
                            if let img = cached {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                AsyncImage(url: bg.thumbnailUrl) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Color(white: 0.85)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                }
                .buttonStyle(.plain)
                .dsHoverScale()
                .help(bg.label)
            }
        }
    }

    private func selectCMSBackground(_ bg: RemoteBackground) {
        Task {
            let url = bg.imageUrl
            let cached = BackgroundPanel.imageCache.object(forKey: url as NSURL)
            let data: Data?
            if let img = cached {
                data = img.pngData()
            } else {
                data = try? await URLSession.shared.data(from: url).0
            }
            guard let png = data else { return }
            await MainActor.run { apply(.image(png)) }
        }
    }

    // MARK: Background-modus — Original (bovenaan) + Transparent (E24.31)

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
        HStack(spacing: DSSpacing.gap2) {
            // "Original" — alleen als de originele foto bewaard is.
            if let original = originalImage {
                modeSwatch(isSelected: portrait?.useOriginalBackground == true,
                           help: "Original background") {
                    Image(nsImage: original).resizable().scaledToFill()
                } action: { selectOriginal() }
            }
            // "Transparent" — de vrijstaande cutout (default).
            modeSwatch(isSelected: isTransparentSelected, help: "Transparent (cut-out)") {
                ZStack {
                    DSColor.Background.neutral
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
            } action: { selectTransparent() }
        }
        .padding(.vertical, DSSpacing.gap2)
        .padding(.leading, DSSpacing.gap1)
    }

    private func modeSwatch(
        isSelected: Bool, help: String,
        @ViewBuilder content: () -> some View, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .fill(DSColor.Background.neutral)
                .frame(width: swatch, height: swatch)
                .overlay { content() }
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .strokeBorder(DSColor.Foreground.primary, lineWidth: isSelected ? 2 : 0)
                }
        }
        .buttonStyle(.plain)
        .dsHoverScale()
        .help(help)
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

            GenerateBackgroundSwatch(
                context: .portrait,
                entitlement: entitlement,
                swatchSize: swatch,
                onSaved: { data in
                    let stored = customImages.add(data) ?? data
                    apply(.image(stored))
                }
            )

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

            // Gradient-presets: CMS-gestuurd als aanwezig, anders hardgecodeerde fallback.
            if cmsGradients.isEmpty {
                ForEach(Array(BackgroundKit.gradientPresets.enumerated()), id: \.offset) { _, colors in
                    Button { selectGradient(colors) } label: {
                        RoundedRectangle(cornerRadius: DSRadius.lg)
                            .fill(BackgroundKit.gradient(colors))
                            .frame(width: swatch, height: swatch)
                    }
                    .buttonStyle(.plain)
                    .dsHoverScale()
                }
            } else {
                ForEach(cmsGradients, id: \.label) { g in
                    if let from = Color(hexRGB: g.fromHex), let to = Color(hexRGB: g.toHex) {
                        Button { selectGradient([from, to]) } label: {
                            RoundedRectangle(cornerRadius: DSRadius.lg)
                                .fill(BackgroundKit.gradient([from, to]))
                                .frame(width: swatch, height: swatch)
                        }
                        .buttonStyle(.plain)
                        .dsHoverScale()
                    }
                }
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
                    .appliedAppearancePreference()
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
                            .frame(width: swatch * 3, height: swatch)
                            .overlay { Image(nsImage: img).resizable().scaledToFill() }
                            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                            .overlay(
                                RoundedRectangle(cornerRadius: DSRadius.lg)
                                    .strokeBorder(
                                        isCurrent ? DSColor.Action.primary : .clear,
                                        lineWidth: DSBorderWidth.medium
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
