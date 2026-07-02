// Gedeeld rechtermuis-menu voor portret-tegels (Home + alle Portraits-lenzen).
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

    @State private var moveFlyoutOpen = false

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.gap1) {
            DSContextMenuPanel(minWidth: isBulk ? 230 : 190) {
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
        DSMenuRow("Align \(n)", icon: "align.horizontal.left") {
            onDismiss()
            PortraitSetActions.align(targets, undoManager: undoManager) { model.setBusyMessage = $0 }
        }
        DSMenuRow("Match lighting to this", icon: "sun.max") {
            onDismiss()
            PortraitSetActions.matchLighting(
                targets, reference: portrait, undoManager: undoManager
            ) { model.setBusyMessage = $0 }
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

// MARK: - Overlay helper

struct PortraitContextMenuOverlay: View {
    @Binding var target: Portrait2?
    let anchor: CGRect
    let model: ShellModel
    let folders: [Folder2]
    let selectedTargets: () -> [Portrait2]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @State private var deleteTargets: [Portrait2] = []
    // E36.5 (audit-B5): "New folder…" vraagt eerst een naam (zelfde prompt als
    // de left-nav-flow) i.p.v. stil "Untitled folder N" te maken. De targets
    // worden vastgehouden tot de alert bevestigd/geannuleerd is.
    @State private var newFolderTargets: [Portrait2] = []
    @State private var newFolderName = ""

    var body: some View {
        Group {
            if let portrait = target {
                DSContextMenuOverlay(anchor: anchor, onDismiss: { target = nil }) {
                    PortraitDSContextMenu(
                        portrait: portrait,
                        model: model,
                        folders: folders,
                        selectedTargets: selectedTargets,
                        undoManager: undoManager,
                        onDismiss: { target = nil },
                        onRequestDelete: { deleteTargets = $0 },
                        onRequestNewFolder: {
                            newFolderName = ""
                            newFolderTargets = $0
                        }
                    )
                }
            }
        }
        .alert("Create folder", isPresented: Binding(
            get: { !newFolderTargets.isEmpty },
            set: { if !$0 { newFolderTargets = [] } }
        )) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { confirmCreateFolder() }
            Button("Cancel", role: .cancel) { newFolderTargets = [] }
        }
        .confirmationDialog(
            deleteTargets.count >= 2
                ? "Delete \(deleteTargets.count) portraits?"
                : "Delete this portrait?",
            isPresented: Binding(
                get: { !deleteTargets.isEmpty },
                set: { if !$0 { deleteTargets = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                for p in deleteTargets { modelContext.delete(p) }
                model.clearPortraitSelection()
                deleteTargets = []
            }
            Button("Cancel", role: .cancel) { deleteTargets = [] }
        } message: {
            Text("This can't be undone.")
        }
    }

    /// Maakt de map met de opgegeven naam (spiegelt `LeftNavView.
    /// confirmCreateFolder`) en verplaatst de vastgehouden portretten erin.
    /// Lege naam = niets doen (alert sluit; geen stille "Untitled folder").
    private func confirmCreateFolder() {
        defer { newFolderTargets = [] }
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let folder = Folder2(name: name, order: folders.count + 1)
        modelContext.insert(folder)
        for p in newFolderTargets { p.folder = folder }
    }
}

// MARK: - View extensions

extension View {
    func portraitContextMenuTrigger(
        portrait: Portrait2,
        model: ShellModel,
        target: Binding<Portrait2?>,
        anchor: Binding<CGRect>
    ) -> some View {
        contextMenuTrigger(in: PortraitContextMenuSpace.coordinateSpace) { frame in
            model.preparePortraitContextMenu(on: portrait)
            target.wrappedValue = portrait
            anchor.wrappedValue = frame
        }
    }

    func portraitContextMenuOverlay(
        target: Binding<Portrait2?>,
        anchor: CGRect,
        model: ShellModel,
        folders: [Folder2],
        selectedTargets: @escaping () -> [Portrait2]
    ) -> some View {
        overlay {
            PortraitContextMenuOverlay(
                target: target,
                anchor: anchor,
                model: model,
                folders: folders,
                selectedTargets: selectedTargets
            )
        }
    }
}
