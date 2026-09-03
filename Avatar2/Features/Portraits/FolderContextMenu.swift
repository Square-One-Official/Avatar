// Gedeeld map-menu (E50.1/E50.5): map-brede acties + Rename/Duplicate/Delete.
// Eén bron voor elke plek waar een map een menu heeft — de map-rij in de
// left-nav, de maptitel in de Portraits-header en de "Folder …"-flyout in het
// tegel-menu op Home/Portraits — zodat een nieuwe map-actie overal tegelijk
// verschijnt. DS-paneel, geen native `.contextMenu`.

import AvatarUI
import SwiftData
import SwiftUI

struct FolderDSContextMenu: View {
    let folder: Folder2
    /// De inhoud van de map in lens-volgorde (`FolderSetScope.items`).
    let items: [Portrait2]
    /// Alle mappen — voor een unieke kopienaam bij Duplicate.
    let folders: [Folder2]
    let model: ShellModel
    let modelContext: ModelContext
    let undoManager: UndoManager?
    let onDismiss: () -> Void
    var minWidth: CGFloat = 210

    var body: some View {
        DSContextMenuPanel(minWidth: minWidth) {
            rows
        }
    }

    @ViewBuilder private var rows: some View {
        let folderID = folder.persistentModelID
        DSMenuRow("Select all in folder", icon: "checkmark.circle", disabled: items.isEmpty) {
            onDismiss()
            model.showPortraits(folderID: folderID)
            model.selectAllPortraits(items.map(\.persistentModelID))
        }
        DSMenuRow("Match framing", icon: "square.resize", shortcut: "⌥⌘F", disabled: items.isEmpty) {
            onDismiss()
            PortraitSetActions.matchFraming(items, undoManager: undoManager, reporter: model.setActionReporter)
        }
        if AppFeatureFlags.matchLightingEnabled {
            DSMenuRow("Match lighting", icon: "sun.max", disabled: items.count < 2) {
                onDismiss()
                PortraitSetActions.matchLighting(items, undoManager: undoManager, reporter: model.setActionReporter)
            }
        }
        DSMenuRow("Export set", icon: "square.and.arrow.up.on.square", disabled: items.isEmpty) {
            onDismiss()
            PortraitSetActions.export(items, isPro: model.isPro, reporter: model.setActionReporter)
        }
        Divider().padding(.vertical, 2)
        DSMenuRow("Default background…", icon: "photo.on.rectangle") {
            onDismiss()
            model.showFolderBackgroundPicker(folderID: folderID)
        }
        Divider().padding(.vertical, 2)
        DSMenuRow("Rename", icon: "pencil") {
            onDismiss()
            model.presentation.alert = .renameFolder(folderID: folderID, draft: folder.name)
        }
        // E50.5: kopie van de map mét alle portretten — werk in de kopie (bv.
        // een effect op het hele team) zonder het origineel te raken. Opent de
        // nieuwe map; Undo in de pill.
        DSMenuRow("Duplicate", icon: "plus.square.on.square") {
            onDismiss()
            let copy = FolderDuplicator.perform(
                folder,
                existingNames: folders.map(\.name),
                modelContext: modelContext,
                undoManager: undoManager,
                reporter: model.setActionReporter,
                onUndo: { removed in
                    if model.selectedFolderID == removed.persistentModelID {
                        model.showPortraits(folderID: folderID)
                    }
                }
            )
            model.isPortraitsExpanded = true
            model.showPortraits(folderID: copy.folder.persistentModelID)
        }
        Divider().padding(.vertical, 2)
        DSMenuRow("Delete", icon: "trash", destructive: true) {
            onDismiss()
            model.presentation.confirm = .deleteFolder(folderID: folderID)
        }
    }
}
