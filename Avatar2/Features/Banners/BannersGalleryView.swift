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

    @State private var headerHeight: CGFloat = 0
    @State private var renaming: BannerDoc?
    @State private var draftName = ""
    @State private var menuBanner: BannerDoc?
    @State private var menuAnchor: CGRect = .zero

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
        .coordinateSpace(name: Self.contextMenuSpace)
        .overlay { contextMenu }
        .alert("Rename banner", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("Banner name", text: $draftName)
            Button("Save") {
                if let b = renaming, !draftName.trimmingCharacters(in: .whitespaces).isEmpty {
                    b.name = draftName; b.touch()
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // MARK: Grid

    @ViewBuilder private var gridArea: some View {
        if banners.isEmpty {
            BannersEmptyState(
                onMake: { makeBanner() },
                onPreset: { layers in makeBanner(from: layers) }
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: DSSpacing.gap4) {
                    ForEach(banners) { banner in
                        BannerGridTile(banner: banner) { frame in
                            menuBanner = banner
                            menuAnchor = frame
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
                    .foregroundStyle(DSColor.Foreground.muted)
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

    // MARK: Context menu

    @ViewBuilder private var contextMenu: some View {
        if menuBanner != nil {
            DSContextMenuOverlay(anchor: menuAnchor, onDismiss: { menuBanner = nil }) {
                if let banner = menuBanner {
                    DSContextMenuPanel {
                        DSMenuRow("Rename", icon: "pencil") {
                            menuBanner = nil
                            draftName = banner.name
                            renaming = banner
                        }
                        DSMenuRow("Duplicate", icon: "plus.square.on.square") {
                            menuBanner = nil
                            duplicate(banner)
                        }
                        Divider().padding(.vertical, 2)
                        DSMenuRow("Delete", icon: "trash", destructive: true) {
                            menuBanner = nil
                            modelContext.delete(banner)
                        }
                    }
                }
            }
        }
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

    var body: some View {
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
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(DSColor.Foreground.muted)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous)
                        .strokeBorder(
                            hovering ? DSColor.Action.primary : DSColor.Foreground.divider,
                            lineWidth: hovering ? DSBorderWidth.medium : DSBorderWidth.thin
                        )
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .dsMotion(DSMotion.micro, value: hovering)
                .onTapGesture { onOpen() }
                .help("Click to open")
                .contextMenuTrigger(in: .named("bannersContextMenu"), onTrigger: onContextMenu)

            Text(banner.name.isEmpty ? "Untitled banner" : banner.name)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.subtle)
                .lineLimit(1)
        }
    }
}

/// E36.2 — Banners-empty-state: kop + "Make banner" + een raster presets
/// (lokale fallback; CMS-presets volgen in E39.2). Klik = open de Studio.
private struct BannersEmptyState: View {
    let onMake: () -> Void
    let onPreset: (BannerLayers) -> Void

    /// Lokale fallback-presets (worden in E39.2 door CMS-presets aangevuld/vervangen).
    static let presets: [BannerLayers] = [
        BannerLayers(fill: .meshGradient(stops: [MeshStop(hex: "#6EC6FF", x: 0, y: 0), MeshStop(hex: "#E3F2FF", x: 1, y: 1)])),
        BannerLayers(fill: .meshGradient(stops: [MeshStop(hex: "#FFB4A2", x: 0, y: 0), MeshStop(hex: "#E7C6FF", x: 1, y: 1)])),
        BannerLayers(fill: .meshGradient(stops: [MeshStop(hex: "#2C3E50", x: 0, y: 0), MeshStop(hex: "#4CA1AF", x: 1, y: 1)])),
        BannerLayers(fill: .solid(hex: "#1C1917")),
        BannerLayers(fill: .meshGradient(stops: [MeshStop(hex: "#B5EAD7", x: 0, y: 0), MeshStop(hex: "#C7CEEA", x: 1, y: 1)])),
        BannerLayers(fill: .solid(hex: "#D5F466")),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.gap6) {
                VStack(spacing: DSSpacing.gap2) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(DSColor.Foreground.muted)
                    Text("Make your first banner")
                        .dsTextStyle(.h3).foregroundStyle(DSColor.Foreground.primary)
                    Text("A wide cover for LinkedIn, X and more — also usable behind your profile picture.")
                        .dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.muted)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                DSPrimaryButton("Make banner") { onMake() }

                VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                    Text("Or start from a preset")
                        .dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: DSSpacing.gap3)], spacing: DSSpacing.gap3) {
                        ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, layers in
                            Button { onPreset(layers) } label: { presetCard(layers) }
                                .buttonStyle(.plain)
                                .dsHoverScale()
                        }
                    }
                }
                .frame(maxWidth: 640)
            }
            .padding(DSSpacing.gap8)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func presetCard(_ layers: BannerLayers) -> some View {
        fillPreview(layers.fill)
            .aspectRatio(1500.0 / 500.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                    .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
            )
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
