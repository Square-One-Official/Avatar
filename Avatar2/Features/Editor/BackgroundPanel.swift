// Background-paneel (E07.1) — Notion-cover-picker-model (besluit Thierry,
// 2026-07-03, aangescherpt met audit-ronde 2):
//   - Tab-header: Gallery · Unsplash · Upload · Generate; rechts twee
//     modus-pills "Original" / "None" (de vage "Remove" is vervallen).
//   - Gallery: verticaal scrollend 4-koloms grid met sectiekoppen — Color &
//     Gradient (picker-"+", DS-kleuren, brand colors met hover-verwijderen,
//     gradients) en de CMS-categorieën mét tegel-labels (Notion-stijl).
//   - Unsplash: zoekveld + editorial/zoek-grid via de /v1/unsplash-proxy
//     (attributie onder elke tegel, download-registratie bij apply).
//   - Upload: "+"-tegel + de persistente eigen uploads (E24.24).
//   - Generate: inline composer à la Notion AI — promptveld + type-dropdown
//     (General/Photo/Pattern) die de server-side promptcompositie écht
//     aanstuurt; Apple-tier valt terug op de E42-sheet (Image Playground).
// Een keuze schrijft op het Portrait2 (kleur xor afbeelding); het canvas
// toont de achtergrond live (E07.2 doet de exportkwaliteit-compositing).
// Elke tegel toont zijn selected-state.

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
    /// Benodigd voor de CMS/Unsplash-fetches en de generatie; optioneel zodat
    /// bestaande aanroeplocaties zonder entitlement blijven werken.
    var entitlement: EntitlementModel? = nil
    /// UX-audit: banners-als-achtergrond (E40) is een matched-background-
    /// concept (Social Preview), geen generieke achtergrond-keuze. De sectie
    /// verschijnt alleen als de aanroeper er expliciet om vraagt — de portret-
    /// editor en het board doen dat niet.
    var showsBanners: Bool = false

    private enum PickerTab: Hashable { case gallery, unsplash, generate }
    @State private var tab: PickerTab = .gallery

    @State private var brand = BrandColorKit.shared
    // E24.24: persistente custom-achtergrond-uploads (herbruikbare tegels).
    @State private var customImages = BackgroundImageKit.shared
    // E25.2: DSColorPicker vanuit de "+"-tegel in Color & Gradient.
    @State private var showColorPicker = false
    @State private var pickerColor: Color = .white
    // Hover-state voor het verwijder-kruisje op brand-kleuren (audit #1).
    @State private var hoveredBrandHex: String?
    // CMS-achtergronden (E33+). Sessie-cache zodat herhaalbaar openen
    // geen flits geeft; leeg = nog niet geladen (geen fallback nodig).
    @State private var cmsBackgrounds: [RemoteBackground] = BackgroundPanel.sessionCache
    // CMS-gradient-presets (E33+). Leeg = fallback op BackgroundKit.gradientPresets.
    @State private var cmsGradients: [RemoteGradientPreset] = BackgroundPanel.gradientCache
    // Unsplash (audit #5). Editorial feed sessie-gecachet; zoeken is live.
    @State private var unsplashQuery = ""
    @State private var unsplashResults: [UnsplashPhoto] = BackgroundPanel.unsplashCache
    @State private var unsplashEnabled: Bool? = BackgroundPanel.unsplashEnabledCache
    @State private var unsplashLoading = false
    // Inline generate-composer (audit #3). De sessie-state leeft BUITEN de
    // view (BackgroundGenerateSession.shared): de popover wordt bij sluiten
    // vernietigd, maar een lopende generatie moet doorlopen én zichtbaar
    // blijven wanneer de gebruiker terugkomt (UX-audit ronde 4).
    @State private var generateSession = BackgroundGenerateSession.shared
    @State private var showTypeMenu = false
    // E40.1: gemaakte banners als achtergrond-bron (BannerDoc-previews).
    @Query(sort: \BannerDoc.updatedAt, order: .reverse) private var bannerDocs: [BannerDoc]
    private var savedBanners: [BannerDoc] { bannerDocs.filter { $0.previewImageData != nil } }

    private static var sessionCache: [RemoteBackground] = []
    private static var gradientCache: [RemoteGradientPreset] = []
    private static var unsplashCache: [UnsplashPhoto] = []
    private static var unsplashEnabledCache: Bool?

    // UX-audit: welke bron (gradient/CMS/Unsplash) de huidige `.image`-bytes
    // leverde, vastgelegd op apply-moment (bron-key → content-signature).
    // Nodig omdat die bronnen de volle resolutie toepassen (≠ thumbnail-bytes)
    // of pas bij keuze renderen. Sessie-scope: na een herstart is alleen deze
    // highlight kwijt, de achtergrond zelf niet.
    private static var appliedSourceSignatures: [String: Int] = [:]
    // Custom uploads zijn wél persistent vergelijkbaar: signature van de
    // opgeslagen PNG, één keer per id berekend (scheelt disk-reads per render).
    private static var customImageSignatures: [String: Int] = [:]

    /// Brede Notion-achtige tegels, 16:10. Unsplash wrapt in 4 kolommen
    /// (paneel is 440pt); de Gallery-rijen scrollen horizontaal met een
    /// vaste tegelbreedte.
    private let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: DSSpacing.gap2),
        count: 4
    )
    private let tileAspect: CGFloat = 16.0 / 10.0
    private let rowTileWidth: CGFloat = 96
    /// Vaste content-hoogte zodat het paneel niet verspringt bij tab-wissel
    /// (zelfde geest als de pixelvaste breadcrumb, UXS-28).
    private let contentHeight: CGFloat = 360

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
            case .unsplash: unsplashTab
            case .generate: generateTab
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await loadCMSBackgrounds() }
        // Ronde 4: opent het paneel terwijl er nog gegenereerd wordt, toon
        // dan direct de Generate-tab met de lopende status i.p.v. Gallery.
        .onAppear { if generateSession.isGenerating { tab = .generate } }
    }

    // MARK: Header — tabs links, Original/None-pills rechts (audit #4)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: DSSpacing.gap4) {
                tabButton("Gallery", .gallery)
                if entitlement != nil { tabButton("Unsplash", .unsplash) }
                if showsGenerateTab {
                    // Mini-spinner in de tab zelf: ook vanuit Gallery/Unsplash
                    // zichtbaar dat er een generatie loopt.
                    tabButton("Generate", .generate,
                              showsProgress: generateSession.isGenerating)
                }
                Spacer()
                modePills.padding(.bottom, DSSpacing.gap1)
            }
            Rectangle()
                .fill(DSColor.Foreground.divider)
                .frame(height: DSBorderWidth.thin)
        }
    }

    /// Tab-knop met Notion-achtige actieve underline die op de divider ligt.
    /// `showsProgress` toont een mini-spinner vóór het label (lopende generatie).
    private func tabButton(
        _ title: String, _ value: PickerTab, showsProgress: Bool = false
    ) -> some View {
        let isActive = tab == value
        return Button { tab = value } label: {
            HStack(spacing: DSSpacing.gap1) {
                if showsProgress {
                    ProgressView().controlSize(.mini)
                }
                Text(title)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(isActive ? DSColor.Foreground.primary
                                              : DSColor.Foreground.muted)
            }
            .padding(.bottom, DSSpacing.gap2)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(isActive ? DSColor.Foreground.primary : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    /// De achtergrond-modus als expliciete, gelabelde toggle: Original (foto
    /// terug) of None (vrijstaande cutout). Actief = gevulde pill. Een keuze
    /// uit de tabs eronder overschrijft beide (geen van beide actief).
    private var modePills: some View {
        HStack(spacing: DSSpacing.gap1) {
            if originalImage != nil {
                modePill("Original",
                         isActive: portrait?.useOriginalBackground == true,
                         help: "Show the original photo background") { selectOriginal() }
            }
            modePill("None", isActive: isTransparentSelected,
                     help: "No background (transparent cut-out)") { selectTransparent() }
        }
    }

    private func modePill(
        _ label: String, isActive: Bool, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .dsTextStyle(.labelSmall)
                // Nooit wrappen ("Origi/nal") — de pill houdt z'n eigen breedte.
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isActive ? DSColor.Foreground.primary
                                          : DSColor.Foreground.muted)
                .padding(.horizontal, DSSpacing.gap2)
                .padding(.vertical, DSSpacing.gap1)
                .background {
                    Capsule().fill(isActive ? DSColor.Background.neutralStronger : .clear)
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Gallery-tab — Color & Gradient · Uploaded · (Banners) · CMS

    /// Secties stapelen verticaal; elke sectie is een horizontaal scrollende
    /// rij (besluit Thierry: opzij-scrollen behouden, nieuwste uploads links).
    private var galleryTab: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                rowSection("Color & Gradient") { colorAndGradientTiles }
                rowSection("Uploaded") { uploadedTiles }
                if showsBanners, AppFeatureFlags.bannersEnabled, !savedBanners.isEmpty {
                    rowSection("Banners") { bannerTiles }
                }
                ForEach(cmsCategories, id: \.self) { cat in
                    rowSection(cat) { cmsTiles(for: cat) }
                }
            }
        }
        .frame(height: contentHeight)
    }

    /// Uploads als Gallery-sectie (Upload-tab vervallen): "+"-tegel als
    /// upload-entry, daarna de persistente uploads met de nieuwste links.
    @ViewBuilder
    private var uploadedTiles: some View {
        tile(isSelected: false, width: rowTileWidth) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSColor.Foreground.subtle)
        } action: { uploadCustom() }
        .help("Upload an image")

        ForEach(customImages.imageIDs.reversed(), id: \.self) { id in
            if let image = customImages.image(for: id) {
                tile(
                    isSelected: currentImageSignature != nil
                        && currentImageSignature == customSignature(id),
                    width: rowTileWidth
                ) {
                    Image(nsImage: image).resizable().scaledToFill()
                } action: { selectCustomImage(id) }
            }
        }
    }

    @ViewBuilder
    private var colorAndGradientTiles: some View {
        // E25.2: "+"-tegel opent de DSColorPicker (met eigen eyedropper); live
        // bijwerken terwijl de picker open is.
        tile(isSelected: false, width: rowTileWidth) {
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
        // Audit #1 (random shades): bewaar bij sluiten alléén de kleur die
        // daadwerkelijk als achtergrond is toegepast — voorheen groeide de
        // brand-rij met élke picker-sessie een willekeurige tussenstand.
        .onChange(of: showColorPicker) { _, open in
            guard !open, let hex = pickerColor.hexRGB,
                  portrait?.backgroundColorHex == hex else { return }
            brand.add(hex)
        }

        ForEach(Array(BackgroundKit.colorPresets.enumerated()), id: \.offset) { _, color in
            colorTile(color)
        }

        // Audit #1: de kit saneert en capt zelf (near-duplicates samengevouwen,
        // max 12) — toon alles zodat het hover-kruisje zichtbaar effect heeft
        // (geen verborgen voorraad die een verwijderde tint stilletjes vervangt).
        ForEach(brand.hexColors, id: \.self) { hex in
            if let color = Color(hexRGB: hex) {
                colorTile(color, hex: hex)
                    .overlay(alignment: .topTrailing) {
                        if hoveredBrandHex == hex { brandRemoveBadge(hex) }
                    }
                    .onHover { inside in
                        if inside { hoveredBrandHex = hex }
                        else if hoveredBrandHex == hex { hoveredBrandHex = nil }
                    }
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

    private func brandRemoveBadge(_ hex: String) -> some View {
        Button { brand.remove(hex) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(DSColor.Foreground.primary)
                .padding(4)
                .background(DSColor.Background.card, in: Circle())
                .overlay {
                    Circle().strokeBorder(DSColor.Foreground.divider,
                                          lineWidth: DSBorderWidth.thin)
                }
                // Expliciete hit-shape: het kruisje ligt bovenop de tegel-knop;
                // zonder eigen contentShape wint de tegel de click te makkelijk.
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(DSSpacing.gap1)
        .help("Remove this brand colour")
    }

    private func colorTile(_ color: Color, hex providedHex: String? = nil) -> some View {
        let hex = providedHex ?? color.hexRGB
        let isSelected = hex != nil && portrait?.backgroundColorHex == hex
        return tile(isSelected: isSelected, width: rowTileWidth) {
            Rectangle().fill(color)
        } action: { if let hex { selectColor(hex) } }
    }

    private func gradientTile(_ colors: [Color]) -> some View {
        tile(isSelected: isAppliedSource(gradientKey(colors)), width: rowTileWidth) {
            Rectangle().fill(BackgroundKit.gradient(colors))
        } action: { selectGradient(colors) }
    }

    @ViewBuilder
    private func cmsTiles(for category: String) -> some View {
        // Audit #2: CMS-tegels dragen hun label zichtbaar (Notion-stijl),
        // niet alleen als hover-tooltip.
        ForEach(cmsBackgrounds.filter { $0.category == category }) { bg in
            captioned(bg.label) {
                tile(isSelected: isAppliedSource(cmsKey(bg)), width: rowTileWidth) {
                    // E52.1: gedeelde memory/disk-cache + downsampled decode
                    // i.p.v. AsyncImage (URLCache helpt niet: Supabase stuurt
                    // `Cache-Control: no-cache`).
                    RemoteThumbnail(url: bg.thumbnailUrl) {
                        Color(white: 0.85)
                    }
                } action: { selectCMSBackground(bg) }
            }
        }
    }

    // MARK: Unsplash-tab (audit #5) — zoeken + editorial feed via backend-proxy

    private var unsplashTab: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            DSSearchField(placeholder: "Search for an image…", text: $unsplashQuery)
            Group {
                if unsplashEnabled == false {
                    unsplashHint("Unsplash is not configured yet — add an UNSPLASH_ACCESS_KEY to the backend.")
                } else if unsplashResults.isEmpty {
                    if unsplashLoading {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        unsplashHint(unsplashQuery.isEmpty
                                     ? "Photos from Unsplash appear here."
                                     : "No results for “\(unsplashQuery)”.")
                    }
                } else {
                    ScrollView(.vertical) {
                        LazyVGrid(columns: gridColumns, spacing: DSSpacing.gap2) {
                            ForEach(unsplashResults) { photo in
                                captioned(photo.authorName.map { "by \($0)" }) {
                                    tile(isSelected: isAppliedSource("unsplash:" + photo.id)) {
                                        RemoteThumbnail(url: photo.thumbUrl) {
                                            Color(white: 0.85)
                                        }
                                    } action: { selectUnsplash(photo) }
                                }
                            }
                        }
                        .padding(DSSpacing.gap1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: contentHeight)
        .task(id: unsplashQuery) { await loadUnsplash() }
    }

    private func unsplashHint(_ text: String) -> some View {
        Text(text)
            .dsTextStyle(.bodySmall)
            .foregroundStyle(DSColor.Foreground.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, DSSpacing.gap6)
    }

    private func loadUnsplash() async {
        guard let backend = entitlement?.backend else { return }
        let query = unsplashQuery.trimmingCharacters(in: .whitespaces)
        if query.isEmpty, !Self.unsplashCache.isEmpty {
            unsplashResults = Self.unsplashCache
            unsplashEnabled = Self.unsplashEnabledCache
            return
        }
        if !query.isEmpty {
            // Debounce: wacht even op verder typen (task(id:) annuleert de vorige).
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
        }
        unsplashLoading = true
        defer { unsplashLoading = false }
        guard let feed = try? await backend.unsplashPhotos(query: query.isEmpty ? nil : query),
              !Task.isCancelled else { return }
        unsplashEnabled = feed.enabled
        unsplashResults = feed.photos
        if query.isEmpty {
            Self.unsplashCache = feed.photos
            Self.unsplashEnabledCache = feed.enabled
        }
    }

    private func selectUnsplash(_ photo: UnsplashPhoto) {
        Task {
            guard let data = try? await URLSession.shared.data(from: photo.fullUrl).0 else { return }
            await MainActor.run {
                recordAppliedSource("unsplash:" + photo.id, data: data)
                apply(.image(data))
            }
            // Unsplash-guideline: download registreren bij daadwerkelijk gebruik.
            if let location = photo.downloadLocation {
                await entitlement?.backend.unsplashTrackDownload(location)
            }
        }
    }

    // MARK: Generate-tab (audit #3) — inline composer à la Notion AI

    private var generateTab: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap3) {
            if BackgroundGenerationCatalog.defaultModel() == .apple {
                // Apple-tier genereert via de native Image Playground-flow —
                // die heeft de E42-sheet nodig, geen inline composer.
                appleGenerateFallback
            } else {
                composer
                if generateSession.isGenerating {
                    HStack(spacing: DSSpacing.gap2) {
                        ProgressView().controlSize(.small)
                        Text("Generating background…")
                            .dsTextStyle(.labelSmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                    }
                } else if let message = generateSession.errorMessage {
                    Text(message)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.destructive)
                }
                Spacer()
                Text("Generate a custom image using AI based on your description · \(BackgroundGenerationContext.portrait.creditCost) credits")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(height: contentHeight)
        .dsDropdownDismissOverlay(isPresented: $showTypeMenu)
    }

    private var composer: some View {
        @Bindable var session = generateSession
        return VStack(alignment: .leading, spacing: DSSpacing.gap3) {
            TextField(
                "",
                text: $session.prompt,
                prompt: Text("Generate a pattern, artwork, photo…")
                    .foregroundStyle(DSColor.Foreground.muted),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .dsTextStyle(.bodySmall)
            .foregroundStyle(DSColor.Foreground.primary)
            .lineLimit(3...5)
            .onSubmit(runInlineGenerate)
            // Tijdens een lopende generatie: prompt vast (hij hoort bij de
            // run) — stoppen kan via de knop rechts.
            .disabled(generateSession.isGenerating)
            HStack {
                typeChip
                Spacer()
                submitButton
            }
        }
        .padding(DSSpacing.gap3)
        .background {
            RoundedRectangle(cornerRadius: DSRadius.lg).fill(DSColor.Background.neutral)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
        }
    }

    private var typeChip: some View {
        Button { showTypeMenu.toggle() } label: {
            HStack(spacing: DSSpacing.gap1) {
                Image(systemName: generateSession.type.iconName)
                    .font(.system(size: 11, weight: .medium))
                Text(generateSession.type.label).dsTextStyle(.labelSmall)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(DSColor.Foreground.subtle)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 28)
            .background(DSColor.Background.neutral, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(generateSession.isGenerating)
        .help("Choose what to generate")
        // Caret-loos DS-dropdown (geen systeem-popover), boven de chip zoals
        // Notion — onder de chip zit alleen nog de paneel-voet.
        .dsDropdownMenu(isPresented: $showTypeMenu, anchorHeight: 28, placement: .above) {
            DSContextMenuPanel(minWidth: 150) {
                ForEach(BackgroundGenerateType.allCases) { type in
                    DSMenuRow(
                        type.label,
                        icon: type.iconName,
                        shortcut: type == generateSession.type ? "✓" : nil
                    ) {
                        generateSession.type = type
                        showTypeMenu = false
                    }
                }
            }
        }
    }

    private var submitButton: some View {
        let isGenerating = generateSession.isGenerating
        let promptEmpty = generateSession.prompt
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            if isGenerating { generateSession.cancel() } else { runInlineGenerate() }
        } label: {
            ZStack {
                Circle().fill(DSColor.Action.primary)
                if isGenerating {
                    // Klikbaar tijdens de run: stop-teken bovenop de spinner.
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DSColor.Action.onAction)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DSColor.Action.onAction)
                }
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(promptEmpty && !isGenerating)
        .opacity(promptEmpty && !isGenerating ? 0.4 : 1)
        .help(isGenerating ? "Stop generating" : "Generate")
    }

    private var appleGenerateFallback: some View {
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
                    let stored = customImages.add(data) ?? data
                    apply(.image(stored))
                }
            )
            .padding(.horizontal, DSSpacing.gap8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func runInlineGenerate() {
        guard let entitlement else { return }
        // De apply-closure bindt het NU actieve portret (via `apply`): het
        // resultaat landt goed, óók als het paneel intussen gesloten is of
        // de gebruiker ergens anders heen genavigeerd is.
        generateSession.start(entitlement: entitlement) { raw in
            // Bewaren als herbruikbare upload-tegel + meteen toepassen.
            let stored = BackgroundImageKit.shared.add(raw) ?? raw
            apply(.image(stored))
        }
    }

    // MARK: Rij/grid-bouwstenen

    /// Gallery-sectie: kop + horizontaal scrollende tegel-rij.
    @ViewBuilder
    private func rowSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
                .padding(.leading, DSSpacing.gap1)
            scrollRow { content() }
        }
    }

    /// E24-fix: rechter-rand-fade als scroll-affordance + trailing-inset zodat
    /// geen tegel hard tegen de rand wordt afgesneden. E24.10: verticale +
    /// leading-padding zodat de hover-scale niet wordt afgekapt door de
    /// scroll-/mask-grens.
    private func scrollRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DSSpacing.gap2) { content() }
                .padding(.vertical, DSSpacing.gap2)
                .padding(.leading, DSSpacing.gap1)
                .scrollRowTrailingInset()
        }
        // Gedeeld met de andere editor-panelen (zie ScrollRowEdgeFade).
        .horizontalScrollEdgeFade()
    }

    /// Tegel met zichtbaar label eronder (Notion-stijl, audit #2).
    private func captioned<Content: View>(
        _ caption: String?, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            content()
            if let caption {
                Text(caption)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .lineLimit(1)
            }
        }
    }

    /// Gedeelde brede tegel (16:10, Notion-model) met een consistente
    /// 2pt selected-rand voor alle bronnen (kleur, gradient, CMS, upload).
    /// `width` gezet = vaste rij-tegel (horizontale Gallery-rijen);
    /// nil = flexibel in een grid (Unsplash).
    private func tile(
        isSelected: Bool, width: CGFloat? = nil,
        @ViewBuilder content: () -> some View, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: DSRadius.lg)
                .fill(DSColor.Background.neutral)
                .aspectRatio(tileAspect, contentMode: .fit)
                .frame(width: width)
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

    /// Is de bron met deze key (gradient/CMS/Unsplash) de huidige achtergrond?
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

    /// Transparant geselecteerd = cutout zonder achtergrond (geen Original,
    /// geen kleur/afbeelding).
    private var isTransparentSelected: Bool {
        guard let portrait else { return false }
        return !portrait.useOriginalBackground
            && portrait.backgroundColorHex == nil
            && portrait.backgroundImageData == nil
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
                captioned(doc.name.isEmpty ? "Untitled banner" : doc.name) {
                    tile(isSelected: isCurrent, width: rowTileWidth * 2) {
                        Image(nsImage: img).resizable().scaledToFill()
                            .overlay(alignment: .topTrailing) {
                                if isStale { updateBadge }
                            }
                    } action: { applyBanner(doc) }
                }
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

    /// E24.31: terug naar de vrijstaande cutout zonder achtergrond ("None").
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

// MARK: - Inline generate: type + sessie (UX-audit ronde 4)

/// Prompt-type dat de server-side promptcompositie aanstuurt: Photo mapt op
/// de bestaande photorealistic-stijl; General/Pattern sturen via de
/// custom-styletekst (≤120 tekens, zie /v1/generate-background).
enum BackgroundGenerateType: String, CaseIterable, Identifiable {
    case general, photo, pattern

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "General"
        case .photo: "Photo"
        case .pattern: "Pattern"
        }
    }

    var iconName: String {
        switch self {
        case .general: "sparkles"
        case .photo: "photo"
        case .pattern: "infinity"
        }
    }

    var styleKey: BackgroundGenerationStyle {
        self == .photo ? .photorealistic : .custom
    }

    var customStyleText: String {
        switch self {
        case .general: "high quality, cohesive style that best fits the description"
        case .photo: ""
        case .pattern: "seamless repeating pattern, flat all-over graphic texture, no perspective"
        }
    }
}

/// Sessie-state + uitvoering van de inline generate-composer, bewust BUITEN
/// de view: de Background-popover wordt bij sluiten/tab-wissel van de toolbar
/// vernietigd, maar een lopende generatie moet doorlopen en haar status
/// (prompt, spinner, foutmelding) tonen wanneer de gebruiker terugkomt —
/// niet resetten naar een lege composer (UX-audit ronde 4).
@MainActor
@Observable
final class BackgroundGenerateSession {
    static let shared = BackgroundGenerateSession()

    var prompt = ""
    var type: BackgroundGenerateType = .general
    private(set) var isGenerating = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let coordinator = BackgroundGenerationCoordinator()

    /// Start een generatie. De apply-closure wordt op startmoment gebonden
    /// (portret/batch-target van dat moment), dus het resultaat landt goed
    /// óók als het paneel intussen weg is.
    func start(entitlement: EntitlementModel, apply: @escaping @MainActor (Data) -> Void) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        let type = type
        Task {
            defer { isGenerating = false }
            do {
                let raw = try await coordinator.generate(
                    model: BackgroundGenerationCatalog.defaultModel(),
                    context: .portrait,
                    style: type.styleKey,
                    customStyleText: type.customStyleText,
                    view: .any,
                    prompt: text,
                    entitlement: entitlement
                )
                apply(raw)
                prompt = ""
            } catch is CancellationError {
                // Gestopt door de gebruiker — geen melding.
            } catch let error as BackgroundGenerationError {
                if let message = error.errorDescription { errorMessage = message }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Stop-knop in de composer: annuleert de lopende cloud-call.
    func cancel() {
        coordinator.cancel()
    }
}
