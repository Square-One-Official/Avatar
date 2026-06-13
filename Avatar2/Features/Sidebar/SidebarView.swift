// Sidebar/set (E05.4 + E04.5-fix bevinding 8, Figma: App / Sidebar images
// 4011:4986, paneel "Siri AI" 248 breed). Losstaande afgeronde kaart
// (bg Card, r-4xl continuous — zelfde kaarttaal als DSEditPanel; ShellView
// geeft de marge rondom) met DSSearchField (capsule h48, E03.10) bovenin,
// DSSidebarRow-slots (thumb 48, continuous corners; selectie = afgeronde
// Inset-highlight) en de DSAddButton (sidebar-add-besluit 10 jun).
// Thumbnails in Figma zijn placeholderfoto's; wij renderen de cutouts.

import AvatarUI
import SwiftData
import SwiftUI

struct SidebarView: View {
    /// Marge t.o.v. de vensterrand — ShellView gebruikt dezelfde waarde
    /// als padding, de kaartradius rekent er concentrisch mee.
    static let edgeInset: CGFloat = DSSpacing.gap1

    // Laatst bewerkt bovenaan, zoals v1 (punt 13).
    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
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
            DSSearchField(text: $searchText)
                .padding(DSSpacing.gap4)

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
                .padding(.horizontal, DSSpacing.gap4)
                .padding(.top, DSSpacing.gap4)
            }

            DSAddButton("Add portrait") {
                onAdd()
            }
            .padding(DSSpacing.gap4)
        }
        .frame(width: 248)
        .frame(maxHeight: .infinity)
        // Concentrisch met de vensterrand (E03.15, bevinding 17):
        // binnenradius = vensterradius − marge; ShellView zet de kaart op
        // dezelfde `edgeInset`.
        .background(
            DSColor.Background.card,
            in: .rect(
                cornerRadius: DSRadius.concentric(inset: Self.edgeInset),
                style: .continuous
            )
        )
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
