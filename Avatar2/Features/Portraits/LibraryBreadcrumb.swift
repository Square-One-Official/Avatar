// Drill-in-breadcrumb voor de editor (alleen zichtbaar in section == .editor).
// Toont de herkomst-trail: "Home ▸ <Naam>" of "Portraits ▸ <Map|All> ▸ <Naam>".
// De crumbs zijn klikbaar (terug naar Home / naar de map) en links staat een
// back-chevron → model.goBack(). De herkomst komt uit ShellModel.openOrigin.

import AvatarUI
import SwiftData
import SwiftUI

struct LibraryBreadcrumb: View {
    let model: ShellModel
    @Query(sort: \Folder2.createdAt, order: .forward) private var folders: [Folder2]

    var body: some View {
        HStack(spacing: DSSpacing.gap2) {
            Button { model.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.primary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back")

            trail
        }
        .padding(.leading, DSSpacing.gap2)
        .padding(.trailing, DSSpacing.gap3)
        .frame(height: 34)
        .background(DSColor.Background.card, in: Capsule())
        .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
    }

    @ViewBuilder private var trail: some View {
        let name = model.selectedPortrait.map { $0.name.isEmpty ? "Untitled" : $0.name } ?? "Untitled"
        switch model.openOrigin {
        case .home:
            // E35.5: het editor-broodkruim wijst naar Portraits (niet Home) — een
            // portret hoort onder Portraits, ook al is het vanaf Home geopend.
            crumb("Portraits") { model.showPortraits(folderID: nil) }
            sep
            leaf(name)
        case .portraits(let folderID):
            crumb("Portraits") { model.showPortraits(folderID: nil) }
            if let folder = folders.first(where: { $0.persistentModelID == folderID }) {
                sep
                crumb(folder.name) { model.showPortraits(folderID: folderID) }
            }
            sep
            leaf(name)
        }
    }

    private func crumb(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.muted)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .help("Go to \(text)")
    }

    private func leaf(_ text: String) -> some View {
        Text(text)
            .dsTextStyle(.labelBase)
            .foregroundStyle(DSColor.Foreground.primary)
            .lineLimit(1)
    }

    private var sep: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(DSColor.Foreground.muted.opacity(0.7))
    }
}
