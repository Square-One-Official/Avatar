// PoC (left-nav): Home — het overzicht (Granola-stijl). Toont het laatst
// GEOPENDE portret groot (hero, dubbele kolombreedte, vierkant) met de rest
// eronder in een net rooster, op tijd verdeeld in Recent/Earlier.
// Onderin een "Upload new portrait"-balk i.p.v. een ask-anything-veld. Bij een
// lege store toont Home onze bestaande first-use-empty-state (avatars) met een
// welkomsttekst erboven. Net-nieuw scherm — DS-tokens, in de geest van het
// hoofddesign.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct HomeView: View {
    let model: ShellModel
    let entitlement: EntitlementModel

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
    @Query(sort: \Folder2.createdAt, order: .forward) private var folders: [Folder2]
    // E36.3: banners als tweede sectie in het overzicht.
    @Query(sort: \BannerDoc.updatedAt, order: .reverse) private var bannerDocs: [BannerDoc]
    private var savedBanners: [BannerDoc] { bannerDocs.filter { $0.previewImageData != nil } }
    // E39.2: CMS-presets voor de "start from preset"-rij (soft-fail → fallback).
    @State private var presetsModel: BannerPresetsModel

    init(model: ShellModel, entitlement: EntitlementModel) {
        self.model = model
        self.entitlement = entitlement
        _presetsModel = State(initialValue: BannerPresetsModel(backend: entitlement.backend))
    }

    // Vast rooster met duidelijke ruimte ertussen. De tegel zelf
    // (Color.clear + aspectRatio(.fit)) wordt nooit breder dan z'n kolom, dus
    // gewone flexibele kolommen volstaan — geen overloop, echte gaps.
    // UXS-9: maten uit ShellMetrics, gedeeld met de Portraits-gallery.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: ShellMetrics.portraitGridSpacing),
        count: ShellMetrics.portraitGridColumnCount
    )

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hero: het laatst geopende portret (`lastOpenedAt`, gezet door
    /// `openPortrait`); zonder open-historie het nieuwste. Staat als enige,
    /// groot, boven de secties en komt daar niet nog eens in voor.
    private var heroPortrait: Portrait2? {
        HomeSections.heroIndex(portraits.map {
            HomeSections.Entry(updatedAt: $0.updatedAt, lastOpenedAt: $0.lastOpenedAt)
        }).map { portraits[$0] }
    }

    /// Alles behalve de hero, in rasterorde (updatedAt, jongste eerst).
    private var restPortraits: [Portrait2] {
        guard let hero = heroPortrait else { return portraits }
        return portraits.filter { $0.persistentModelID != hero.persistentModelID }
    }

    /// UXS-9 (UX8): secties op TIJD, niet op "de nieuwste is speciaal". Recent =
    /// bewerkt in de laatste week (max `recentSectionLimit`); de rest is Earlier.
    /// De oude indeling zette altijd precies één portret in Recent — ook als dat
    /// van maanden geleden was — en noemde al het andere Earlier.
    private var recentPortraits: [Portrait2] {
        let cutoff = Date().addingTimeInterval(-ShellMetrics.recentSectionWindow)
        return Array(restPortraits.filter { $0.updatedAt >= cutoff }
            .prefix(ShellMetrics.recentSectionLimit))
    }

    private var earlierPortraits: [Portrait2] {
        let recentIDs = Set(recentPortraits.map(\.persistentModelID))
        return restPortraits.filter { !recentIDs.contains($0.persistentModelID) }
    }

    /// Zichtbare volgorde op Home (hero, dan Recent, dan Earlier) — voor
    /// ⇧-bereikselectie, zodat het bereik klopt met wat je ziet.
    private var homeOrder: [PersistentIdentifier] {
        ([heroPortrait].compactMap { $0 } + recentPortraits + earlierPortraits).map(\.persistentModelID)
    }

    var body: some View {
        Group {
            // Een batch-drop op een lege store toont meteen het overzicht met
            // de import-tegels (first-use zou de reveal verbergen).
            if portraits.isEmpty && model.libraryImportJobs.isEmpty {
                firstUse
            } else {
                overview
            }
        }
        // UXS-9: first-use ↔ overzicht wisselde met een harde snap.
        .dsMotion(DSMotion.emphasis, value: portraits.isEmpty)
        .transition(.dsScaleFade(anchor: .center, reduceMotion: reduceMotion))
    }

    /// Eén grid-sectie (kop + tegels) — Recent en Earlier delen exact dezelfde
    /// celmaat en hover-behandeling, want het zijn dezelfde kaarten.
    @ViewBuilder
    private func portraitSection(
        _ title: String, _ items: [Portrait2], imports: [ShellModel.LibraryImportJob] = []
    ) -> some View {
        if !items.isEmpty || !imports.isEmpty {
            VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                Text(title)
                    .dsTextStyle(.labelLarge)
                    .foregroundStyle(DSColor.Foreground.subtle)
                LazyVGrid(columns: columns, spacing: ShellMetrics.portraitGridSpacing) {
                    // Batch-import: tijdelijke tegels vóór de echte (zie
                    // PortraitsGalleryView voor de volgorde-afspraak).
                    ForEach(imports) { job in
                        LibraryImportTile(job: job)
                    }
                    ForEach(items) { portrait in
                        tile(portrait)
                    }
                }
            }
        }
    }

    /// Eén portret-kaart op Home (hero of rastercel) — zelfde klik/selectie/
    /// menu-gedrag; alleen `prominent` verschilt.
    private func tile(_ portrait: Portrait2, prominent: Bool = false) -> some View {
        PortraitGridTile(
            portrait: portrait, folders: folders, model: model,
            isSelected: model.isPortraitSelected(portrait),
            ordered: { homeOrder },
            selectedTargets: { portraits.filter { model.isPortraitSelected($0) } },
            onContextMenu: { frame in
                model.preparePortraitContextMenu(on: portrait)
                model.presentation.openPortraitContextMenu(
                    portraitID: portrait.persistentModelID,
                    anchor: frame,
                    scope: .home
                )
            },
            prominent: prominent,
            // Home is map-overstijgend: toon in welke submap het portret staat.
            showsFolderBadge: true
        )
    }

    /// De hero op precies twee rasterkolommen + één gap: een HStack met twee
    /// gelijke flexibele helften en de grid-spacing ertussen geeft
    /// (W − gap) / 2, wat exact 2·kolom + gap is in het 4-koloms rooster. Zo
    /// lijnt de rechterrand van de hero uit met de tweede kolom eronder, zonder
    /// GeometryReader. Vierkant via de tegel zelf (aspectRatio 1).
    @ViewBuilder
    private func heroSection(_ portrait: Portrait2) -> some View {
        HStack(alignment: .top, spacing: ShellMetrics.portraitGridSpacing) {
            tile(portrait, prominent: true)
                .frame(maxWidth: .infinity)
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    // MARK: - First-use (lege store): welkom + bestaande empty-state

    private var firstUse: some View {
        VStack(spacing: DSSpacing.gap5) {
            VStack(spacing: DSSpacing.gap2) {
                Text("Welcome to Aaavatar")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("Drop a photo or upload one to make your first portrait.")
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, DSSpacing.gap8)
            FirstUseEmptyState(onChooseFile: { model.presentOpenPanel() }, entitlement: entitlement)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Overzicht (niet-lege store)

    private var overview: some View {
        VStack(spacing: 0) {
            header
            overviewBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// UXS-9: "Home" is de paginatitel; Recent/Earlier zijn sectiekoppen
    /// daaronder. Vaste kop met dezelfde insets als de Portraits-gallery
    /// (ShellMetrics.pageTitle*), zodat de titel niet verspringt bij tabwissel.
    private var header: some View {
        Text("Home")
            .dsTextStyle(.h3)
            .foregroundStyle(DSColor.Foreground.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.gap6)
            .padding(.top, ShellMetrics.pageTitleTopInset)
            .padding(.bottom, ShellMetrics.pageTitleBottomInset)
            .background(DSColor.Background.app)
    }

    private var overviewBody: some View {
        ZStack(alignment: .bottom) {
            DSScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.gap6) {
                    if let hero = heroPortrait {
                        heroSection(hero)
                    }
                    portraitSection(
                        "Recent", recentPortraits,
                        imports: model.visibleLibraryImportJobs(folderID: nil)
                    )
                    portraitSection("Earlier", earlierPortraits)

                    // Banners-sectie achter de feature-flag (release zonder banners).
                    if AppFeatureFlags.bannersEnabled {
                        bannersSection
                    }
                }
                .padding(.horizontal, DSSpacing.gap6)
                // UXS-10 (UX9): de zwevende upload-pil mag content niet permanent
                // maskeren. Inset afgeleid uit de pil-maten (ShellMetrics) i.p.v.
                // een los getal, zodat 'ie meebeweegt als de pil verandert.
                .padding(.bottom, ShellMetrics.uploadPillScrollInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            uploadBar
                .padding(.bottom, ShellMetrics.uploadPillBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // CMS-banner-presets alleen laden als de Banners-suite aan staat.
        .task {
            if AppFeatureFlags.bannersEnabled {
                // UXS-5: Home toont dezelfde gebakken previews als de gallery —
                // draai de eenmalige placeholder-sweep+herbake dus ook hier,
                // vóór de banner-sectie stale bakes kan tonen.
                await BannerPlaceholderMigration.runIfNeeded(context: modelContext)
                await presetsModel.load()
            }
        }
        .coordinateSpace(name: PortraitContextMenuSpace.name)
    }

    // MARK: - Banners-sectie (E36.3)

    @ViewBuilder private var bannersSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap3) {
            HStack {
                Text("Banners")
                    .dsTextStyle(.labelLarge)
                    .foregroundStyle(DSColor.Foreground.subtle)
                Spacer()
                Button { model.showBanners() } label: {
                    Text("See all").dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.subtle)
                }
                .buttonStyle(.plain)
                .dsFocusEffectDisabled()
            }
            .padding(.top, DSSpacing.gap2)

            if savedBanners.isEmpty {
                // Nog geen banners → de "start from preset"-rij (E39.2): een
                // maak-tegel gevolgd door CMS-presets (soft-fail → fallback).
                DSScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.gap4) {
                        makeBannerTile
                        ForEach(presetsModel.presets) { preset in
                            homePresetCard(preset)
                        }
                    }
                    .padding(.bottom, DSSpacing.gap1)
                    .scrollRowTrailingInset()
                }
                .horizontalScrollEdgeFade()
            } else {
                DSScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.gap4) {
                        ForEach(savedBanners.prefix(8)) { doc in
                            homeBannerCard(doc)
                        }
                    }
                    .padding(.bottom, DSSpacing.gap1)
                    .scrollRowTrailingInset()
                }
                .horizontalScrollEdgeFade()
            }
        }
    }

    /// Maak-tegel die de Banners-tab opent (zelfde maat als de preset-kaarten).
    private var makeBannerTile: some View {
        Button { model.showBanners() } label: {
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    .strokeBorder(DSColor.Foreground.divider, style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .frame(width: 240, height: 80)
                    .overlay {
                        HStack(spacing: DSSpacing.gap2) {
                            Image(systemName: "plus")
                            Text("Make a banner").dsTextStyle(.labelSmall)
                        }
                        .foregroundStyle(DSColor.Foreground.subtle)
                    }
                Text("New").dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.subtle).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .dsHoverScale(1.02)
    }

    /// Een CMS/fallback-preset-kaart: opent de Banner Studio met de preset
    /// ingeladen als nieuw `BannerDoc` (E39.2).
    private func homePresetCard(_ preset: BannerPresetItem) -> some View {
        Button { makeBanner(from: preset.layers) } label: {
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                // E52.1: gedeelde ThumbnailCache (memory/disk + downsampled
                // decode); zolang de preview laadt rendert de fill als placeholder.
                RemoteThumbnail(url: preset.thumbnailURL) {
                    presetFill(preset.layers.fill)
                }
                .frame(width: 240, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                        .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
                )
                Text(preset.label)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .lineLimit(1)
                    .help(preset.label)
            }
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .dsHoverScale(1.02)
    }

    @ViewBuilder private func presetFill(_ fill: BannerFill) -> some View {
        switch fill {
        case let .solid(hex):
            (Color(hexRGB: hex) ?? .black)
        case let .meshGradient(stops):
            LinearGradient(colors: stops.compactMap { Color(hexRGB: $0.hex) }, startPoint: .topLeading, endPoint: .bottomTrailing)
        case .image:
            DSColor.Background.inset
        }
    }

    /// Maakt een banner vanuit een preset-laagstack en opent de Studio.
    private func makeBanner(from layers: BannerLayers) {
        let doc = BannerDoc(layers: layers)
        modelContext.insert(doc)
        model.openBannerStudio(doc)
    }

    private func homeBannerCard(_ doc: BannerDoc) -> some View {
        Button { model.openBannerStudio(doc) } label: {
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                ZStack {
                    DSColor.Background.inset
                    if let data = doc.previewImageData, let img = NSImage(data: data) {
                        Image(nsImage: img).resizable().scaledToFill()
                    }
                }
                .frame(width: 240, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                        .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
                )
                Text(doc.name.isEmpty ? "Untitled banner" : doc.name)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .lineLimit(1)
                    .help(doc.name.isEmpty ? "Untitled banner" : doc.name)
            }
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .dsHoverScale(1.02)
    }
    private var uploadBar: some View {
        Button { model.presentOpenPanel() } label: {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: DSIconSize.lg, weight: .regular))
                    .foregroundStyle(DSColor.Foreground.subtle)
                Text("Upload portrait")
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.subtle)
                DSBadge("⌘U", type: .neutral)
            }
            .padding(.horizontal, DSSpacing.gap4)
            .frame(height: ShellMetrics.uploadPillHeight)
            .background(DSColor.Background.card, in: Capsule())
            .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
            .dsShadow(.card)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        // ⌘U zelf leeft app-breed in het File-menu (UploadPortraitCommands,
        // E49.2); de knop houdt alleen het badge als visuele hint.
    }
}

// MARK: - Sectie-logica (testbaar, zonder SwiftData)

/// Pure keuze van de Home-hero, gespiegeld in `HomeSectionsTests`.
enum HomeSections {
    struct Entry {
        let updatedAt: Date
        let lastOpenedAt: Date?
    }

    /// Index van de hero in `entries` (rasterorde: updatedAt, jongste eerst):
    /// het laatst geopende portret; heeft niets een open-historie, dan het
    /// eerste (= nieuwste). Leeg → nil.
    static func heroIndex(_ entries: [Entry]) -> Int? {
        guard !entries.isEmpty else { return nil }
        let opened = entries.enumerated().compactMap { i, e in e.lastOpenedAt.map { (i, $0) } }
        if let best = opened.max(by: { $0.1 < $1.1 }) { return best.0 }
        return 0
    }
}
