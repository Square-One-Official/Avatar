// PoC (left-nav): "Portraits"-galerij — Riverside-stijl rooster waarin alle
// portretten in mappen (Folder2) georganiseerd worden. Twee niveaus: een
// overzicht met map-kaarten (collage + naam + telling) en een drill-in met de
// portretten van één map. Dubbelklik op een portret opent het in Studio.
// Net-nieuw scherm (geen Figma-bron) — DS-tokens, in de geest van het hoofddesign.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct PortraitsGalleryView: View {
    let model: ShellModel

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
    @Query(sort: \Folder2.createdAt, order: .forward) private var folders: [Folder2]

    @State private var thumbs = ThumbnailStore()
    /// Geopende map (drill-in). nil = overzicht.
    @State private var openBucket: Bucket?
    /// Map waarvan de naam wordt bewerkt (rename-alert).
    @State private var renamingFolder: Folder2?
    @State private var draftName = ""

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: DSSpacing.gap4)]

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView {
                if let bucket = openBucket {
                    folderDetail(bucket)
                } else {
                    folderGrid
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("Rename folder", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Folder name", text: $draftName)
            Button("Save") {
                if let f = renamingFolder, !draftName.trimmingCharacters(in: .whitespaces).isEmpty {
                    f.name = draftName
                }
                renamingFolder = nil
            }
            Button("Cancel", role: .cancel) { renamingFolder = nil }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: DSSpacing.gap3) {
            if let bucket = openBucket {
                Button { openBucket = nil } label: {
                    HStack(spacing: DSSpacing.gap1) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        Text("Portraits").dsTextStyle(.labelBase)
                    }
                    .foregroundStyle(DSColor.Foreground.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text("/").dsTextStyle(.labelBase).foregroundStyle(DSColor.Foreground.muted)
                Text(bucket.title).dsTextStyle(.h4).foregroundStyle(DSColor.Foreground.primary)
            } else {
                Text("Portraits").dsTextStyle(.h3).foregroundStyle(DSColor.Foreground.primary)
            }
            Spacer(minLength: 0)
            if openBucket == nil {
                DSNeutralButton("New folder", icon: Image(systemName: "folder.badge.plus")) {
                    createFolder()
                }
            }
        }
        .padding(.horizontal, DSSpacing.gap6)
        .padding(.top, 52)
        .padding(.bottom, DSSpacing.gap4)
    }

    // MARK: - Map-overzicht

    private var folderGrid: some View {
        LazyVGrid(columns: columns, spacing: DSSpacing.gap4) {
            ForEach(buckets) { bucket in
                FolderCard(bucket: bucket, thumbs: thumbs) { openBucket = bucket }
                    .contextMenu { bucketContextMenu(bucket) }
            }
        }
        .padding(.horizontal, DSSpacing.gap6)
        .padding(.bottom, DSSpacing.gap6)
    }

    @ViewBuilder
    private func bucketContextMenu(_ bucket: Bucket) -> some View {
        if let folder = bucket.folder {
            Button("Rename") { draftName = folder.name; renamingFolder = folder }
            Button("Delete", role: .destructive) {
                if openBucket?.id == bucket.id { openBucket = nil }
                modelContext.delete(folder)
            }
        }
    }

    // MARK: - Map-detail (portretten in de map)

    private func folderDetail(_ bucket: Bucket) -> some View {
        let items = portraits(in: bucket)
        return Group {
            if items.isEmpty {
                emptyState("No portraits here yet", subtitle: "Move portraits into this folder from the right sidebar.")
            } else {
                LazyVGrid(columns: columns, spacing: DSSpacing.gap4) {
                    ForEach(items) { portrait in
                        PortraitTile(portrait: portrait, thumbs: thumbs) {
                            model.select(portrait)
                            model.showSection(.studio)
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.gap6)
                .padding(.bottom, DSSpacing.gap6)
            }
        }
    }

    private func emptyState(_ title: String, subtitle: String) -> some View {
        VStack(spacing: DSSpacing.gap2) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DSColor.Foreground.muted)
            Text(title).dsTextStyle(.labelLarge).foregroundStyle(DSColor.Foreground.subtle)
            Text(subtitle).dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DSSpacing.gap12)
    }

    // MARK: - Buckets (All + Unfiled + mappen)

    /// Een "bucket" is een tegel in het overzicht: All, Unfiled of een echte map.
    struct Bucket: Identifiable {
        enum Kind: Hashable { case all, unfiled, folder }
        let id: String
        let kind: Kind
        let title: String
        let folder: Folder2?
    }

    private var buckets: [Bucket] {
        var result: [Bucket] = [
            Bucket(id: "all", kind: .all, title: "All portraits", folder: nil)
        ]
        if portraits.contains(where: { $0.folder == nil }) {
            result.append(Bucket(id: "unfiled", kind: .unfiled, title: "Unfiled", folder: nil))
        }
        for folder in folders {
            result.append(Bucket(id: folder.persistentModelID.hashValue.description, kind: .folder, title: folder.name, folder: folder))
        }
        return result
    }

    private func portraits(in bucket: Bucket) -> [Portrait2] {
        switch bucket.kind {
        case .all: return portraits
        case .unfiled: return portraits.filter { $0.folder == nil }
        case .folder: return portraits.filter { $0.folder?.persistentModelID == bucket.folder?.persistentModelID }
        }
    }

    private func createFolder() {
        let n = folders.count + 1
        let folder = Folder2(name: "Untitled folder \(n)", order: n)
        modelContext.insert(folder)
        draftName = folder.name
        renamingFolder = folder
    }
}

// MARK: - Map-kaart (collage + naam + telling)

private struct FolderCard: View {
    let bucket: PortraitsGalleryView.Bucket
    let thumbs: ThumbnailStore
    let onOpen: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var allPortraits: [Portrait2]
    @State private var hovering = false

    private var items: [Portrait2] {
        switch bucket.kind {
        case .all: return allPortraits
        case .unfiled: return allPortraits.filter { $0.folder == nil }
        case .folder: return allPortraits.filter { $0.folder?.persistentModelID == bucket.folder?.persistentModelID }
        }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                collage
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous)
                            .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.title)
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .lineLimit(1)
                }
                .padding(.horizontal, DSSpacing.gap1)
                .padding(.bottom, DSSpacing.gap1)
            }
            .padding(DSSpacing.gap2)
            .background(DSColor.Background.card, in: RoundedRectangle(cornerRadius: DSRadius.xl3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl3, style: .continuous)
                    .strokeBorder(hovering ? DSColor.Foreground.divider : .clear, lineWidth: DSBorderWidth.thin)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dsMotion(DSMotion.micro, value: hovering)
    }

    private var subtitle: String {
        let n = items.count
        let noun = n == 1 ? "portrait" : "portraits"
        if let folder = bucket.folder {
            return "\(folder.createdAt.formatted(date: .abbreviated, time: .omitted)) • \(n) \(noun)"
        }
        return "\(n) \(noun)"
    }

    @ViewBuilder
    private var collage: some View {
        let tiles = Array(items.prefix(4))
        if tiles.isEmpty {
            ZStack {
                DSColor.Background.inset
                Image(systemName: "folder")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(DSColor.Foreground.muted)
            }
        } else if tiles.count == 1 {
            tileImage(tiles[0])
        } else {
            GeometryReader { proxy in
                let spacing: CGFloat = 2
                let w = (proxy.size.width - spacing) / 2
                let h = (proxy.size.height - spacing) / 2
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) {
                        cell(tiles, 0, w, h)
                        cell(tiles, 1, w, h)
                    }
                    HStack(spacing: spacing) {
                        cell(tiles, 2, w, h)
                        cell(tiles, 3, w, h, overflow: items.count - 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ tiles: [Portrait2], _ index: Int, _ w: CGFloat, _ h: CGFloat, overflow: Int = 0) -> some View {
        if index < tiles.count {
            tileImage(tiles[index])
                .frame(width: w, height: h)
                .clipped()
                .overlay {
                    if overflow > 0 {
                        ZStack {
                            Color.black.opacity(0.55)
                            Text("+\(overflow)")
                                .dsTextStyle(.labelBase)
                                .foregroundStyle(.white)
                        }
                    }
                }
        } else {
            DSColor.Background.inset.frame(width: w, height: h)
        }
    }

    @ViewBuilder
    private func tileImage(_ portrait: Portrait2) -> some View {
        if let image = thumbs.thumbnail(for: portrait, maxDimension: 240, adjusted: false) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            DSColor.Background.inset
        }
    }
}

// MARK: - Portret-tegel (in map-detail)

private struct PortraitTile: View {
    let portrait: Portrait2
    let thumbs: ThumbnailStore
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            ZStack {
                DSColor.Background.inset
                if let image = thumbs.thumbnail(for: portrait, maxDimension: 240, adjusted: false) {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous)
                    .strokeBorder(hovering ? DSColor.Action.primary : DSColor.Foreground.divider, lineWidth: hovering ? DSBorderWidth.medium : DSBorderWidth.thin)
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(portrait.name.isEmpty ? "Untitled" : portrait.name)
                    .dsTextStyle(.labelBase).foregroundStyle(DSColor.Foreground.primary).lineLimit(1)
                if !portrait.role.isEmpty {
                    Text(portrait.role).dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, DSSpacing.gap1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .dsMotion(DSMotion.micro, value: hovering)
        .onTapGesture(count: 2) { onOpen() }
        .help("Double-click to open in Studio")
    }
}
