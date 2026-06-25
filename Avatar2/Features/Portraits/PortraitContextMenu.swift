// Gedeeld rechtermuis-menu voor portret-tegels (Home + alle Portraits-lenzen).
// Toont enkel-item-acties, of bulk-acties zodra er ≥2 geselecteerd zijn en op een
// geselecteerd item wordt geklikt (Finder-stijl). De set-acties (Align/Match/
// Export) komen uit `PortraitSetActions` (gelift uit de verwijderde set-sidebar).

import SwiftData
import SwiftUI

@MainActor @ViewBuilder
func portraitContextMenu(
    for portrait: Portrait2,
    model: ShellModel,
    folders: [Folder2],
    selectedTargets: @escaping () -> [Portrait2],
    undoManager: UndoManager?,
    modelContext: ModelContext
) -> some View {
    let ids = model.selectedPortraitIDs
    let isBulk = ids.count >= 2 && ids.contains(portrait.persistentModelID)
    if isBulk {
        let targets = selectedTargets()
        Button("Export \(targets.count) portraits…") {
            PortraitSetActions.export(targets, isPro: model.isPro) { model.setBusyMessage = $0 }
        }
        portraitMoveMenu("Move \(targets.count) to folder", targets: targets, folders: folders, modelContext: modelContext)
        Button("Align \(targets.count)") {
            PortraitSetActions.align(targets, undoManager: undoManager) { model.setBusyMessage = $0 }
        }
        Button("Match lighting to this") {
            PortraitSetActions.matchLighting(targets, reference: portrait, undoManager: undoManager) { model.setBusyMessage = $0 }
        }
        Divider()
        Button("Delete \(targets.count)", role: .destructive) {
            for p in targets { modelContext.delete(p) }
            model.clearPortraitSelection()
        }
    } else {
        Button("Open") { model.openPortrait(portrait) }
        portraitMoveMenu("Move to folder", targets: [portrait], folders: folders, modelContext: modelContext)
        Button("Export…") { model.select(portrait); model.exportCurrentPortrait() }
        Divider()
        Button("Delete", role: .destructive) { modelContext.delete(portrait) }
    }
}

@MainActor @ViewBuilder
private func portraitMoveMenu(_ title: String, targets: [Portrait2], folders: [Folder2], modelContext: ModelContext) -> some View {
    Menu(title) {
        Button("Unfiled") { for p in targets { p.folder = nil } }
        if !folders.isEmpty { Divider() }
        ForEach(folders) { folder in
            Button(folder.name) { for p in targets { p.folder = folder } }
        }
        Divider()
        Button("New folder…") {
            let f = Folder2(name: "Untitled folder \(folders.count + 1)", order: folders.count + 1)
            modelContext.insert(f)
            for p in targets { p.folder = f }
        }
    }
}
