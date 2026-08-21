// Gedeeld rechtermuis-menu voor portret-tegels (Home + Portraits-grid).
// DS-paneel i.p.v. native `.contextMenu`. Toont enkel-item-acties, of bulk-acties
// zodra er ≥2 geselecteerd zijn en op een geselecteerd item wordt geklikt
// (Finder-stijl).

import AvatarUI
import SwiftData
import SwiftUI

/// Naam voor de coordinate space waarin menu-ankers gemeten worden.
enum PortraitContextMenuSpace {
    static let name = "portraitContextMenu"
    static var coordinateSpace: CoordinateSpace { .named(name) }
}

// MARK: - Zwevend menu (DS)

struct PortraitDSContextMenu: View {
    let portrait: Portrait2
    let model: ShellModel
    let folders: [Folder2]
    let selectedTargets: () -> [Portrait2]
    let undoManager: UndoManager?
    let onDismiss: () -> Void
    let onRequestDelete: ([Portrait2]) -> Void
    let onRequestNewFolder: ([Portrait2]) -> Void
    let onRequestSetBackground: ([Portrait2]) -> Void

    @State private var moveFlyoutOpen = false

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.gap1) {
            DSContextMenuPanel(minWidth: isBulk ? 250 : 190) {
                if isBulk {
                    bulkRows
                } else {
                    singleRows
                }
            }
            if moveFlyoutOpen {
                moveFlyout
            }
        }
    }

    private var isBulk: Bool {
        let ids = model.selectedPortraitIDs
        return ids.count >= 2 && ids.contains(portrait.persistentModelID)
    }

    @ViewBuilder private var singleRows: some View {
        DSMenuRow("Open", icon: "arrow.up.forward") {
            onDismiss(); model.openPortrait(portrait)
        }
        DSMenuRow("Move to folder", icon: "folder", showsChevron: true) {
            moveFlyoutOpen.toggle()
        }
        DSMenuRow("Export…", icon: "square.and.arrow.up") {
            onDismiss(); model.select(portrait); model.exportCurrentPortrait()
        }
        Divider().padding(.vertical, 2)
        DSMenuRow("Delete", icon: "trash", destructive: true) {
            onDismiss(); onRequestDelete([portrait])
        }
    }

    @ViewBuilder private var bulkRows: some View {
        let targets = selectedTargets()
        let n = targets.count
        DSMenuRow("Export \(n) portraits…", icon: "square.and.arrow.up.on.square") {
            onDismiss()
            PortraitSetActions.export(targets, isPro: model.isPro) { model.setBusyMessage = $0 }
        }
        DSMenuRow("Move \(n) to folder", icon: "folder", showsChevron: true) {
            moveFlyoutOpen.toggle()
        }
        DSMenuRow("Match framing", icon: "square.resize", shortcut: "⌥⌘F") {
            onDismiss()
            PortraitSetActions.matchFraming(targets, undoManager: undoManager) { model.setBusyMessage = $0 }
        }
        DSMenuRow("Match lighting", icon: "sun.max", shortcut: "⌥⌘L") {
            onDismiss()
            PortraitSetActions.matchLighting(
                targets, reference: portrait, undoManager: undoManager
            ) { model.setBusyMessage = $0 }
        }
        DSMenuRow("Set background…", icon: "photo", shortcut: "⇧⌘B") {
            onRequestSetBackground(targets)
        }
        Divider().padding(.vertical, 2)
        DSMenuRow("Delete \(n)", icon: "trash", destructive: true) {
            onDismiss(); onRequestDelete(targets)
        }
    }

    private var moveFlyout: some View {
        let targets = isBulk ? selectedTargets() : [portrait]
        return DSContextMenuPanel(minWidth: 180) {
            DSMenuRow("Unfiled", icon: "tray") {
                onDismiss()
                for p in targets { p.folder = nil }
            }
            if !folders.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(folders) { folder in
                    DSMenuRow(folder.name, icon: "folder") {
                        onDismiss()
                        for p in targets { p.folder = folder }
                    }
                }
            }
            Divider().padding(.vertical, 2)
            // E36.5 (audit-B5): geen stille "Untitled folder N" meer — vraag
            // altijd een naam (zelfde prompt als de left-nav-flow); de overlay
            // toont de alert en maakt de map pas na bevestiging.
            DSMenuRow("New folder…", icon: "folder.badge.plus") {
                onDismiss()
                onRequestNewFolder(targets)
            }
        }
    }
}

// MARK: - View extensions

extension View {
    func portraitContextMenuTrigger(
        portrait: Portrait2,
        model: ShellModel,
        scope: ContextMenuScope
    ) -> some View {
        contextMenuTrigger(in: PortraitContextMenuSpace.coordinateSpace) { frame in
            model.preparePortraitContextMenu(on: portrait)
            model.presentation.openPortraitContextMenu(
                portraitID: portrait.persistentModelID,
                anchor: frame,
                scope: scope
            )
        }
    }
}
