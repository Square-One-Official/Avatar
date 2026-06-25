// Gallery-lens voor de Portraits-surface (Finder-stijl): één grote preview boven
// + een horizontale filmstrip onder. Klik een filmstrip-thumb = focus (preview
// wisselt); ⌘/⇧-klik = multi-select; klik de grote preview = openen in de editor.
// Rechtermuis = enkel/bulk-menu. Selectie leest mee met `model.selectedPortraitIDs`.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct GalleryLens: View {
    let items: [Portrait2]
    let model: ShellModel
    let folders: [Folder2]

    @State private var focusID: PersistentIdentifier?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager

    private var focused: Portrait2? {
        items.first { $0.persistentModelID == focusID } ?? items.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if let f = focused { preview(f) } else { Spacer() }
            filmstrip
        }
    }

    // MARK: - Grote preview

    private func preview(_ p: Portrait2) -> some View {
        VStack(spacing: DSSpacing.gap3) {
            PortraitComposite(portrait: p, maxDimension: 1200)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl3, style: .continuous))
                .frame(maxWidth: 520)
            VStack(spacing: 2) {
                Text(p.name.isEmpty ? "Untitled" : p.name)
                    .dsTextStyle(.h4).foregroundStyle(DSColor.Foreground.primary)
                if !p.role.isEmpty {
                    Text(p.role).dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DSSpacing.gap6)
        .contentShape(Rectangle())
        .onTapGesture { model.openPortrait(p) }
        .help("Click to open in the editor")
        .contextMenu { menu(p) }
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.gap3) {
                ForEach(items) { p in filmThumb(p) }
            }
            .padding(.horizontal, DSSpacing.gap6)
            .padding(.vertical, DSSpacing.gap4)
        }
        .frame(height: 116)
        .background(DSColor.Background.card)
        .overlay(alignment: .top) {
            Rectangle().fill(DSColor.Foreground.divider).frame(height: DSBorderWidth.thin)
        }
    }

    private func filmThumb(_ p: Portrait2) -> some View {
        let isFocus = p.persistentModelID == focused?.persistentModelID
        let isSel = model.isPortraitSelected(p)
        return PortraitComposite(portrait: p, maxDimension: 200)
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous)
                    .strokeBorder(
                        (isFocus || isSel) ? DSColor.Action.primary : DSColor.Foreground.divider,
                        lineWidth: (isFocus || isSel) ? DSBorderWidth.medium : DSBorderWidth.thin
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isSel {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(DSColor.Background.app, DSColor.Action.primary)
                        .padding(3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                let mods = NSApp.currentEvent?.modifierFlags ?? []
                if mods.contains(.command) || mods.contains(.shift) {
                    model.handlePortraitClick(p, ordered: items.map(\.persistentModelID), mods: mods)
                } else {
                    focusID = p.persistentModelID
                }
            }
            .dsMotion(DSMotion.micro, value: isFocus)
            .contextMenu { menu(p) }
    }

    @ViewBuilder private func menu(_ p: Portrait2) -> some View {
        portraitContextMenu(
            for: p, model: model, folders: folders,
            selectedTargets: { items.filter { model.isPortraitSelected($0) } },
            undoManager: undoManager, modelContext: modelContext
        )
    }
}
