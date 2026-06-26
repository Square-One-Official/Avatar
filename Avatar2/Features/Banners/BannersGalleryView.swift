// Banners-bibliotheek (E35.3 → E36.1). Een overzicht van je gemaakte banners,
// nét als Portraits: een zwevende header (titel + telling + "Make banner") boven
// een rooster van WIJDE banner-tegels met hover-rand en naam-overlay; rechtsklik
// = Rename/Duplicate/Delete. De gradient-snel-maker is weg (E36.1, besluit
// Thierry 2026-06-26): banners maak je voortaan in de Banner Studio (E37); upload
// is een secundaire route binnen die flow. Net-nieuw scherm — DS-tokens, in de
// geest van het hoofddesign.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct BannersGalleryView: View {
    let model: ShellModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Banner2.updatedAt, order: .reverse) private var banners: [Banner2]

    /// Gemeten hoogte van de zwevende header → top-inset voor de grid.
    @State private var headerHeight: CGFloat = 0
    @State private var renaming: Banner2?
    @State private var draftName = ""
    @State private var menuBanner: Banner2?
    @State private var menuAnchor: CGRect = .zero

    private static let contextMenuSpace = "bannersContextMenu"

    // Wijde tegels — een paar naast elkaar, schaalt met de breedte.
    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 480), spacing: DSSpacing.gap4)]

    var body: some View {
        // Zelfde zwevende-header-aanpak als PortraitsGalleryView: de header zweeft
        // bovenaan (vult nooit mee, verdwijnt dus nooit), de grid krijgt een
        // top-inset ter grootte van de gemeten header.
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
            // Empty-state ("Make banner" + presets) komt in E36.2; tot dan een
            // rustige plaatshouder in de geest van de Portraits-empty-state.
            VStack(spacing: DSSpacing.gap2) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(DSColor.Foreground.muted)
                Text("No banners yet")
                    .dsTextStyle(.labelLarge).foregroundStyle(DSColor.Foreground.subtle)
                Text("Make a banner to use behind your profile picture.")
                    .dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: DSSpacing.gap4) {
                    ForEach(banners) { banner in
                        BannerGridTile(banner: banner) { frame in
                            menuBanner = banner
                            menuAnchor = frame
                        } onOpen: {
                            // TODO(E37.2): open de Banner Studio op dit document.
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

    /// Maakt een nieuwe banner. TODO(E37.2): open de lege Banner Studio. Tot die
    /// er is, blijft upload de werkende creatie-route (wordt in E37 secundair).
    private func makeBanner() {
        uploadBanner()
    }

    private func uploadBanner() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        let banner = Banner2(name: url.deletingPathExtension().lastPathComponent, imageData: data)
        modelContext.insert(banner)
    }

    private func duplicate(_ banner: Banner2) {
        let base = banner.name.isEmpty ? "Untitled banner" : banner.name
        let copy = Banner2(name: "\(base) copy", imageData: banner.imageData)
        modelContext.insert(copy)
    }
}

/// Wijde banner-tegel (3:1) met hover-rand en naam-overlay — spiegelt
/// `PortraitGridTile`, maar wijd en zonder multi-select. Klik opent (later) de
/// Banner Studio; rechtsklik triggert het contextmenu.
private struct BannerGridTile: View {
    let banner: Banner2
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
                        if let img = NSImage(data: banner.imageData) {
                            Image(nsImage: img).resizable().scaledToFill()
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

/// Meet de zwevende-header-hoogte zodat de grid er precies onder begint.
private struct BannersHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
