// Banners-bibliotheek (E35.3 → E36.1 → E37.2). Een overzicht van je gemaakte
// banners, nét als Portraits: een zwevende header (titel + telling + "Make
// banner") boven een rooster van WIJDE banner-tegels met hover-rand en
// naam-overlay; rechtsklik = Rename/Duplicate/Delete. De gradient-snel-maker is
// weg (E36.1). Sinds E37.2 is de canonieke store `BannerDoc` (een bewerkbaar
// document): "Make banner" en tegel-klik openen de Banner Studio. De
// social-preview-compat (oude `Banner2` → BannerChooser/-Resolver) wordt in 37.6
// verzoend; tot dan toont deze gallery de BannerDoc-previews.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct BannersGalleryView: View {
    let model: ShellModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BannerDoc.updatedAt, order: .reverse) private var banners: [BannerDoc]

    /// CMS-presets (E39.2) voor de empty-state; soft-fail → lokale fallback.
    @State private var presetsModel: BannerPresetsModel

    init(model: ShellModel, entitlement: EntitlementModel) {
        self.model = model
        _presetsModel = State(initialValue: BannerPresetsModel(backend: entitlement.backend))
    }

    @State private var headerHeight: CGFloat = 0

    private static let contextMenuSpace = "bannersContextMenu"

    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 480), spacing: DSSpacing.gap4)]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                gridArea
                    .frame(width: geo.size.width,
                           height: max(0, geo.size.height - headerHeight),
                           alignment: .top)
                    .clipped()
                    .padding(.top, headerHeight)
                header
                    .background(
                        GeometryReader { hGeo in
                            Color.clear.preference(key: BannersHeaderHeightKey.self, value: hGeo.size.height)
                        }
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onPreferenceChange(BannersHeaderHeightKey.self) { headerHeight = $0 }
        .task {
            // 37.18: eenmalige sweep van legacy placeholder-lagen + herbake
            // van hun stale previews, vóór de tegels renderen.
            await BannerPlaceholderMigration.runIfNeeded(context: modelContext)
            await presetsModel.load()
        }
        .coordinateSpace(name: Self.contextMenuSpace)
    }

    // MARK: Grid

    @ViewBuilder private var gridArea: some View {
        if banners.isEmpty {
            BannersEmptyState(
                presetsModel: presetsModel,
                onMake: { makeBanner() },
                onPreset: { layers in makeBanner(from: layers) }
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: DSSpacing.gap4) {
                    ForEach(banners) { banner in
                        BannerGridTile(banner: banner) { frame in
                            model.presentation.bannerGalleryMenu = ContextMenuRequest(
                                portraitID: nil,
                                folderID: nil,
                                bannerID: banner.persistentModelID,
                                anchor: frame,
                                scope: .home
                            )
                        } onOpen: {
                            model.openBannerStudio(banner)
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.gap6)
                .padding(.bottom, DSSpacing.gap6)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: DSSpacing.gap4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Banners")
                    .dsTextStyle(.h3)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("\(banners.count) \(banners.count == 1 ? "banner" : "banners")")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
            Spacer(minLength: 0)
            DSPrimaryButton("Make banner") { makeBanner() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.gap6)
        .padding(.top, DSSpacing.gap8)
        .padding(.bottom, DSSpacing.gap4)
        .background(DSColor.Background.app)
    }

    // MARK: Acties

    /// Maakt een nieuw, leeg banner-document en opent het in de Banner Studio.
    private func makeBanner() {
        let doc = BannerDoc()
        modelContext.insert(doc)
        model.openBannerStudio(doc)
    }

    /// Maakt een banner vanuit een preset-laagstack en opent de Studio.
    private func makeBanner(from layers: BannerLayers) {
        let doc = BannerDoc(layers: layers)
        modelContext.insert(doc)
        model.openBannerStudio(doc)
    }

    private func duplicate(_ banner: BannerDoc) {
        let base = banner.name.isEmpty ? "Untitled banner" : banner.name
        let copy = BannerDoc(
            name: "\(base) copy",
            canvasSize: banner.canvasSize,
            layers: banner.layers,
            fillImageData: banner.fillImageData,
            logoImageData: banner.logoImageData,
            previewImageData: banner.previewImageData
        )
        modelContext.insert(copy)
    }
}

/// Wijde banner-tegel (3:1) met hover-rand en naam-overlay — spiegelt
/// `PortraitGridTile`, maar wijd en zonder multi-select. Klik opent de Banner
/// Studio; rechtsklik triggert het contextmenu. Toont de gerenderde
/// `previewImageData` (nil = nog niet bewaard → plaatshouder).
private struct BannerGridTile: View {
    let banner: BannerDoc
    let onContextMenu: (CGRect) -> Void
    let onOpen: () -> Void

    @State private var hovering = false

    private var displayName: String {
        banner.name.isEmpty ? "Untitled banner" : banner.name
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                Color.clear
                    .aspectRatio(1500.0 / 500.0, contentMode: .fit)
                    .overlay {
                        ZStack {
                            DSColor.Background.inset
                            if let data = banner.previewImageData, let img = NSImage(data: data) {
                                Image(nsImage: img).resizable().scaledToFill()
                            } else {
                                Image(systemName: "rectangle.on.rectangle.angled")
                                    .font(.system(size: DSIconSize.xl, weight: .light))
                                    .foregroundStyle(DSColor.Foreground.subtle)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous)
                            .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous)
                            .strokeBorder(
                                hovering ? DSColor.Action.primaryForeground : .clear,
                                lineWidth: DSBorderWidth.medium
                            )
                    )
                    .contentShape(Rectangle())

                Text(displayName)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .lineLimit(1)
                    .help(displayName)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dsMotion(DSMotion.micro, value: hovering)
        .accessibilityLabel(displayName)
        .accessibilityHint("Opens the banner in the studio")
        .help("Open \(displayName)")
        .contextMenuTrigger(in: .named("bannersContextMenu"), onTrigger: onContextMenu)
    }
}

/// E36.2 + E39.2 — Banners-empty-state: kop + "Make banner" + een raster
/// presets. De presets komen uit het CMS (`BannerPresetsModel`, soft-fail →
/// lokale fallback). Een CMS-preset met preview-URL toont z'n thumbnail; anders
/// (of voor lokale fallbacks) rendert de kaart de fill zelf. Klik = open de
/// Studio met de preset ingeladen.
private struct BannersEmptyState: View {
    let presetsModel: BannerPresetsModel
    let onMake: () -> Void
    let onPreset: (BannerLayers) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.gap6) {
                VStack(spacing: DSSpacing.gap2) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: DSIconSize.xxl, weight: .light))
                        .foregroundStyle(DSColor.Foreground.subtle)
                    Text("Make your first banner")
                        .dsTextStyle(.h3).foregroundStyle(DSColor.Foreground.primary)
                    Text("A wide cover for LinkedIn, X and more — also usable behind your profile picture.")
                        .dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.subtle)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                DSPrimaryButton("Make banner") { onMake() }

                VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                    Text("Or start from a preset")
                        .dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.subtle)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: DSSpacing.gap3)], spacing: DSSpacing.gap3) {
                        ForEach(presetsModel.presets) { preset in
                            Button { onPreset(preset.layers) } label: { presetCard(preset) }
                                .buttonStyle(.plain)
                                .dsHoverScale(1.02)
                        }
                    }
                }
                .frame(maxWidth: 640)
            }
            .padding(DSSpacing.gap8)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func presetCard(_ preset: BannerPresetItem) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            // E52.1: gedeelde ThumbnailCache (memory/disk + downsampled decode);
            // zolang de CMS-preview laadt rendert de fill als placeholder.
            RemoteThumbnail(url: preset.thumbnailURL) {
                fillPreview(preset.layers.fill)
            }
            .aspectRatio(1500.0 / 500.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                    .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
            )
            Text(preset.label)
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.subtle)
                .lineLimit(1)
                .help(preset.label)
        }
    }

    @ViewBuilder private func fillPreview(_ fill: BannerFill) -> some View {
        switch fill {
        case let .solid(hex):
            (Color(hexRGB: hex) ?? .black)
        case let .meshGradient(stops):
            LinearGradient(colors: stops.compactMap { Color(hexRGB: $0.hex) }, startPoint: .topLeading, endPoint: .bottomTrailing)
        case .image:
            DSColor.Background.inset
        }
    }
}

/// Meet de zwevende-header-hoogte zodat de grid er precies onder begint.
private struct BannersHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
