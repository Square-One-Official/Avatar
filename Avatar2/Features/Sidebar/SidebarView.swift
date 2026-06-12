// Sidebar/set (E05.4, Figma: App / Sidebar images 4011:4986, paneel "Siri
// AI" 248 breed). Search bovenin (DSTextField h40 als stand-in voor de
// Figma "Search input"-component h48 — DS-story E03.10), daaronder
// DSSidebarRow-slots (thumb 48 uit de cutout, naam/rol, selectie = bg
// Inset) en de DSAddButton (sidebar-add-besluit 10 jun). Thumbnails in
// Figma zijn placeholderfoto's; wij renderen de echte cutouts.

import AvatarUI
import SwiftData
import SwiftUI

struct SidebarView: View {
    @Query(sort: \Portrait2.createdAt) private var portraits: [Portrait2]
    @State private var searchText = ""

    let selectedID: PersistentIdentifier?
    let onSelect: (Portrait2) -> Void
    let onAdd: () -> Void

    private var filtered: [Portrait2] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return portraits }
        return portraits.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.role.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DSTextField(
                placeholder: "Search",
                icon: Image(systemName: "magnifyingglass"),
                text: $searchText
            )
            .padding(DSSpacing.gap3)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { portrait in
                        DSSidebarRow(
                            name: portrait.name.isEmpty ? "Name" : portrait.name,
                            role: portrait.role.isEmpty ? "Role" : portrait.role,
                            isSelected: portrait.persistentModelID == selectedID,
                            action: { onSelect(portrait) },
                            avatar: { thumbnail(for: portrait) }
                        )
                    }
                }
                .padding(.horizontal, DSSpacing.gap3)
                .padding(.top, DSSpacing.gap3)
            }

            DSAddButton("Add portrait") {
                onAdd()
            }
            .padding(DSSpacing.gap3)
        }
        .frame(width: 248)
        .frame(maxHeight: .infinity)
        .background(DSColor.Background.card)
    }

    @ViewBuilder
    private func thumbnail(for portrait: Portrait2) -> some View {
        if let image = NSImage(data: portrait.cutoutData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            DSColor.Background.inset
        }
    }
}
