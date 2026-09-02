// Drill-in-breadcrumb voor de editor (alleen zichtbaar in section == .editor).
// Toont de herkomst-trail: "Portraits ▸ <Naam>" of "Portraits ▸ <Map> ▸ <Naam>".
// De crumbs zijn klikbaar (terug naar Portraits / naar de map) en links staat
// een back-chevron → model.goBack(). De naam-leaf opent dezelfde rename-modal
// als de canvas-chip (lege naam → "Add name"). Herkomst: ShellModel.openOrigin.

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
                    .font(.system(size: DSIconSize.sm, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.primary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
            .dsHoverHighlight(cornerRadius: DSRadius.md)
            .help("Back")

            trail
        }
        .padding(.leading, DSSpacing.gap1_5)
        .padding(.trailing, DSSpacing.gap2)
        .frame(height: 28)
        .background(DSColor.Background.card, in: Capsule())
        .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
    }

    @ViewBuilder private var trail: some View {
        let rawName = model.selectedPortrait?.name ?? ""
        let hasName = !rawName.isEmpty
        let name = hasName ? rawName : "Add name"
        switch model.openOrigin {
        case .home:
            // E35.5: het editor-broodkruim wijst naar Portraits (niet Home) — een
            // portret hoort onder Portraits, ook al is het vanaf Home geopend.
            crumb("Portraits") { model.showPortraits(folderID: nil) }
            sep
            leaf(name, isPlaceholder: !hasName)
        case .portraits(let folderID):
            crumb("Portraits") { model.showPortraits(folderID: nil) }
            if let folder = folders.first(where: { $0.persistentModelID == folderID }) {
                sep
                crumb(folder.name) { model.showPortraits(folderID: folderID) }
            }
            sep
            leaf(name, isPlaceholder: !hasName)
        }
    }

    private func crumb(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.muted)
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.gap1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .dsHoverHighlight(cornerRadius: DSRadius.md)
        .help("Go to \(text)")
    }

    private func leaf(_ text: String, isPlaceholder: Bool) -> some View {
        Button { model.isShowingRename = true } label: {
            Text(text)
                .dsTextStyle(.labelBase)
                .foregroundStyle(isPlaceholder ? DSColor.Foreground.muted : DSColor.Foreground.primary)
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.gap1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .dsHoverHighlight(cornerRadius: DSRadius.md)
        .help(isPlaceholder ? "Add name" : "Rename")
        .accessibilityLabel(isPlaceholder ? "Add name" : "Rename \(text)")
    }

    private var sep: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: DSIconSize.xxs, weight: .semibold))
            .foregroundStyle(DSColor.Foreground.muted.opacity(0.7))
    }
}
