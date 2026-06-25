// List-lens voor de Portraits-surface: volle-breedte rijen (DSSidebarRow) met een
// gecomponeerde thumbnail + naam/rol. De gedeelde selectie + rechtermuis-acties
// (Phase 1) hangen eraan: gewone klik = openen, ⌘/⇧-klik = multi-select,
// rechtermuis = enkel/bulk-menu. De rij-highlight (lime rand + check) leest mee
// met `model.selectedPortraitIDs`, net als de grid-tegels.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct ListLens: View {
    let items: [Portrait2]
    let model: ShellModel
    let folders: [Folder2]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { p in
                    DSSidebarRow(
                        name: p.name.isEmpty ? "Untitled" : p.name,
                        role: p.role.isEmpty ? nil : p.role,
                        isMultiSelected: model.isPortraitSelected(p),
                        action: {
                            model.handlePortraitClick(
                                p, ordered: items.map(\.persistentModelID),
                                mods: NSApp.currentEvent?.modifierFlags ?? []
                            )
                        },
                        avatar: { PortraitComposite(portrait: p, maxDimension: 96) }
                    )
                    .contextMenu {
                        portraitContextMenu(
                            for: p, model: model, folders: folders,
                            selectedTargets: { items.filter { model.isPortraitSelected($0) } },
                            undoManager: undoManager, modelContext: modelContext
                        )
                    }
                }
            }
            .padding(.horizontal, DSSpacing.gap6)
            .padding(.bottom, DSSpacing.gap6)
        }
    }
}
