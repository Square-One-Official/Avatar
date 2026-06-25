// PoC (left-nav): Portraits-grid — toont de beelden van de in de sidebar
// geselecteerde map (of álle beelden) in een NET rooster van max 3 naast
// elkaar. De mappen zelf wonen nu in de left-nav (inklapbare Portraits-sectie),
// niet meer als kaarten hier. Dubbelklik opent een portret in de editor;
// rechtermuis verplaatst het naar een map of verwijdert het. Net-nieuw scherm —
// DS-tokens, in de geest van het hoofddesign.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct PortraitsGalleryView: View {
    let model: ShellModel

    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
    @Query(sort: \Folder2.createdAt, order: .forward) private var folders: [Folder2]
    @State private var thumbs = ThumbnailStore()

    // "max 3 naast elkaar" — een vast 3-koloms rooster.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: DSSpacing.gap4), count: 3)

    private var selectedFolder: Folder2? {
        guard let id = model.selectedFolderID else { return nil }
        return folders.first { $0.persistentModelID == id }
    }

    private var items: [Portrait2] {
        guard let id = model.selectedFolderID else { return portraits }
        return portraits.filter { $0.folder?.persistentModelID == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: DSSpacing.gap4) {
                        ForEach(items) { portrait in
                            PortraitGridTile(portrait: portrait, thumbs: thumbs, folders: folders, model: model) {
                                model.openPortrait(portrait)
                            }
                        }
                    }
                    .padding(.horizontal, DSSpacing.gap6)
                    .padding(.bottom, DSSpacing.gap6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(selectedFolder?.name ?? "All portraits")
                .dsTextStyle(.h3)
                .foregroundStyle(DSColor.Foreground.primary)
            Text("\(items.count) \(items.count == 1 ? "portrait" : "portraits")")
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DSSpacing.gap6)
        .padding(.top, DSSpacing.gap8)
        .padding(.bottom, DSSpacing.gap4)
    }

    private var emptyState: some View {
        VStack(spacing: DSSpacing.gap2) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DSColor.Foreground.muted)
            Text(model.selectedFolderID == nil ? "No portraits yet" : "This folder is empty")
                .dsTextStyle(.labelLarge).foregroundStyle(DSColor.Foreground.subtle)
            Text("Right-click a portrait to move it into a folder.")
                .dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Gedeelde portret-tegel (Home + Portraits-grid). Vierkant, met naam/rol eronder.
/// Dubbelklik opent de editor; rechtermuis verplaatst naar een map of verwijdert.
struct PortraitGridTile: View {
    let portrait: Portrait2
    let thumbs: ThumbnailStore
    let folders: [Folder2]
    let model: ShellModel
    let onOpen: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var hovering = false

    var body: some View {
        // Vierkante tegel via het canonieke Color.clear + aspectRatio(.fit) +
        // overlay-patroon — robuust in een LazyVGrid (nooit groter dan de kolom,
        // dus geen overloop/overlap). De tegel toont de ECHTE compositie zoals de
        // editor: de gekozen achtergrond (kleur/afbeelding/origineel) met het
        // vrijstaande onderwerp erover — niet langer de kale cutout.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { composed }
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
            .onTapGesture(count: 2) { onOpen() }
            .help("Double-click to open in the editor")
        .contextMenu {
            Button("Open") { onOpen() }
            Menu("Move to folder") {
                Button("Unfiled") { portrait.folder = nil }
                if !folders.isEmpty { Divider() }
                ForEach(folders) { folder in
                    Button(folder.name) { portrait.folder = folder }
                }
                Divider()
                Button("New folder…") {
                    let f = Folder2(name: "Untitled folder \(folders.count + 1)", order: folders.count + 1)
                    modelContext.insert(f)
                    portrait.folder = f
                }
            }
            Divider()
            Button("Delete", role: .destructive) { modelContext.delete(portrait) }
        }
    }

    // De compositie binnen het vierkant: de gedeelde achtergrond+onderwerp-
    // render + de naam/rol-overlay onderin.
    @ViewBuilder
    private var composed: some View {
        ZStack(alignment: .bottomLeading) {
            PortraitComposite(portrait: portrait, maxDimension: 280)

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(portrait.name.isEmpty ? "Untitled" : portrait.name)
                    .dsTextStyle(.labelBase).foregroundStyle(.white).lineLimit(1)
                if !portrait.role.isEmpty {
                    Text(portrait.role).dsTextStyle(.labelSmall).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
            }
            .padding(DSSpacing.gap3)
        }
    }
}

/// Gedeelde portret-compositie. Rendert via dezelfde `PortraitExporter`-pijplijn
/// als de export/editor (achtergrond + de OPGESLAGEN transform/zoom + Adjust),
/// als een vierkant — zo matchen de framing/cropping en de achtergrond in elke
/// thumbnail exact wat de editor toont (i.p.v. een kale, anders-gekadreerde
/// cutout). Resultaat wordt gecachet op (portret, updatedAt, maat).
struct PortraitComposite: View {
    let portrait: Portrait2
    let maxDimension: CGFloat

    @State private var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        ZStack {
            DSColor.Background.inset
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: cacheKey) { load() }
    }

    private var cacheKey: String {
        "\(portrait.persistentModelID.hashValue)-\(portrait.updatedAt.timeIntervalSince1970)-\(Int(maxDimension))"
    }

    @MainActor
    private func load() {
        let key = cacheKey as NSString
        if let cached = Self.cache.object(forKey: key) { image = cached; return }
        // Altijd vierkant (uniforme tegels); de transform/achtergrond komen exact
        // uit de editor-pijplijn. Geen watermerk op een thumbnail.
        guard let data = PortraitExporter.makePNG(
            for: portrait, watermark: false, side: Int(maxDimension), shape: .square
        ), let img = NSImage(data: data) else { return }
        Self.cache.setObject(img, forKey: key)
        image = img
    }
}
