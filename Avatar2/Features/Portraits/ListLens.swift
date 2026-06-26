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

    @State private var menuTarget: Portrait2?
    @State private var menuAnchor: CGRect = .zero

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
                        avatar: {
                            // Hero-morph-bron: de rij opent het portret, dus de morph
                            // vertrekt vanaf de rij-thumbnail. Zie [[HeroMorph]].
                            PortraitComposite(portrait: p, maxDimension: 96)
                                .heroPortrait(p.persistentModelID, isSource: true)
                        }
                    )
                    .portraitContextMenuTrigger(
                        portrait: p, model: model, target: $menuTarget, anchor: $menuAnchor
                    )
                }
            }
            .padding(.horizontal, DSSpacing.gap6)
            .padding(.bottom, DSSpacing.gap6)
        }
        .coordinateSpace(name: PortraitContextMenuSpace.name)
        .portraitContextMenuOverlay(
            target: $menuTarget,
            anchor: menuAnchor,
            model: model,
            folders: folders,
            selectedTargets: { items.filter { model.isPortraitSelected($0) } }
        )
    }
}
