// PoC (left-nav): Granola-stijl linker navigatie — de enige sidebar (de oude
// rechter set-sidebar is verdwenen). Bovenin een subtiele inklap-toggle náást
// de traffic-lights; daaronder Home (overzicht) en een INKLAPBARE Portraits-
// sectie die de mappen toont (+ een plus om een map te maken, rechtermuis om te
// hernoemen/verwijderen). Onderin de upgrade-banner + quota en een klikbare
// gebruikersrij (Settings / Manage backgrounds / Sign out). Net-nieuw scherm
// (geen Figma-bron) — gebouwd op de bestaande DS-tokens.

import AvatarUI
import SwiftData
import SwiftUI

struct LeftNavView: View {
    let model: ShellModel
    let entitlement: EntitlementModel

    /// Breedte in lijn met Granola; iets smaller dan de oude set-sidebar.
    static let width: CGFloat = 236
    static let edgeInset: CGFloat = ShellMetrics.windowEdgeInset

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder2.createdAt, order: .forward) private var folders: [Folder2]

    @State private var showUserMenu = false
    @State private var renamingFolder: Folder2?
    @State private var draftName = ""
    /// De map waarboven nu een portret zweeft (drop-highlight). Eén tegelijk.
    @State private var dropTargetedFolderID: PersistentIdentifier?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reserveer de strook voor de OS traffic-lights. Flush sidebar:
            // de strip is 44 pt (traffic-lights zitten op ~y=12 → nav-items
            // starten op y=44, geeft ~28 pt lucht onder de groene knop).
            Color.clear
                .frame(height: 44)

            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                    LeftNavRow(
                        icon: Image(systemName: "house"),
                        title: "Home",
                        isSelected: model.section == .home && !model.isShowingSettings
                    ) {
                        model.showHome()
                    }

                    portraitsSection
                }
                .padding(.horizontal, DSSpacing.gap2)
                .padding(.top, DSSpacing.gap2)
            }

            Spacer(minLength: DSSpacing.gap2)

            upgradeBanner
                .padding(.horizontal, DSSpacing.gap2)
                .padding(.bottom, DSSpacing.gap2)

            Divider()
                .overlay(DSColor.Foreground.divider)
                .padding(.horizontal, DSSpacing.gap3)

            userRow
                .padding(DSSpacing.gap2)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        // Flush aan de linker/boven/onderkant van het venster: geen radius links
        // (macOS knipt de venstercorners zelf af). Rechts concentrisch t.o.v.
        // de 4 pt trailing-inset die ShellView toepast.
        .background(DSColor.Background.card)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: DSRadius.concentric(inset: Self.edgeInset),
                topTrailingRadius: DSRadius.concentric(inset: Self.edgeInset),
                style: .continuous
            )
        )
        // Subtiele scheidingslijn rechts (kleur-verschil alleen is niet genoeg
        // in Light mode wanneer card ≈ white en content ook bijna white is).
        .overlay(alignment: .trailing) {
            DSColor.Foreground.divider
                .frame(width: DSBorderWidth.thin)
                .ignoresSafeArea()
        }
        .task { await entitlement.refresh() }
        .alert("Rename folder", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Folder name", text: $draftName)
            Button("Save") {
                if let f = renamingFolder, !draftName.trimmingCharacters(in: .whitespaces).isEmpty {
                    f.name = draftName
                }
                renamingFolder = nil
            }
            Button("Cancel", role: .cancel) { renamingFolder = nil }
        }
    }

    // MARK: - Portraits (inklapbaar) + mappen

    private var portraitsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            // Kop: chevron + label (klik = uitklappen + naar 'alle beelden'),
            // plus een "+" om een map te maken.
            HStack(spacing: DSSpacing.gap1) {
                Button {
                    model.togglePortraitsExpanded()
                    model.showPortraits(folderID: nil)
                } label: {
                    HStack(spacing: DSSpacing.gap2) {
                        Image(systemName: model.isPortraitsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DSColor.Foreground.muted)
                            .frame(width: 12)
                        Image(systemName: "square.grid.2x2")
                            .resizable().scaledToFit().frame(width: 16, height: 16)
                        Text("Portraits").dsTextStyle(.labelBase)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(isPortraitsAllSelected ? DSColor.Foreground.primary : DSColor.Foreground.subtle)
                    .padding(.horizontal, DSSpacing.gap2)
                    .frame(height: 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isPortraitsAllSelected ? DSColor.Background.neutralStronger : .clear,
                        in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { createFolder() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DSColor.Foreground.muted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Create folder")
            }

            if model.isPortraitsExpanded {
                ForEach(folders) { folder in
                    folderRow(folder)
                }
                if folders.isEmpty {
                    Text("No folders yet")
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .padding(.leading, 38)
                        .padding(.vertical, DSSpacing.gap1)
                }
            }
        }
    }

    private func folderRow(_ folder: Folder2) -> some View {
        let isSelected = model.section == .portraits
            && model.selectedFolderID == folder.persistentModelID
            && !model.isShowingSettings
        let isDropTargeted = dropTargetedFolderID == folder.persistentModelID
        return Button {
            model.showPortraits(folderID: folder.persistentModelID)
        } label: {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 16)
                Text(folder.name).dsTextStyle(.labelBase).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected || isDropTargeted ? DSColor.Foreground.primary : DSColor.Foreground.subtle)
            .padding(.leading, 26)
            .padding(.trailing, DSSpacing.gap2)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isDropTargeted ? DSColor.Action.primary.opacity(0.18)
                    : (isSelected ? DSColor.Background.neutralStronger : .clear),
                in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            )
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                        .strokeBorder(DSColor.Action.primary, lineWidth: DSBorderWidth.medium)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Drop-doel: sleep een portret hier naartoe om het in deze map te zetten.
        .dropDestination(for: PortraitDragItem.self) { items, _ in
            move(items, into: folder)
        } isTargeted: { targeted in
            if targeted {
                dropTargetedFolderID = folder.persistentModelID
            } else if dropTargetedFolderID == folder.persistentModelID {
                dropTargetedFolderID = nil
            }
        }
        .dsMotion(DSMotion.micro, value: isDropTargeted)
        .contextMenu {
            Button("Rename") { draftName = folder.name; renamingFolder = folder }
            Button("Delete", role: .destructive) {
                if model.selectedFolderID == folder.persistentModelID { model.selectedFolderID = nil }
                modelContext.delete(folder)
            }
        }
    }

    /// Verplaats de gesleepte portretten naar `folder` (haalt het echte Portrait2
    /// op via de SwiftData-identiteit uit de drag-payload). `true` als er minstens
    /// één daadwerkelijk verplaatst is.
    private func move(_ items: [PortraitDragItem], into folder: Folder2) -> Bool {
        var moved = false
        for item in items {
            guard let portrait = modelContext.model(for: item.id) as? Portrait2 else { continue }
            portrait.folder = folder
            moved = true
        }
        return moved
    }

    private var isPortraitsAllSelected: Bool {
        model.section == .portraits && model.selectedFolderID == nil && !model.isShowingSettings
    }

    private func createFolder() {
        let n = folders.count + 1
        let folder = Folder2(name: "Untitled folder \(n)", order: n)
        modelContext.insert(folder)
        model.isPortraitsExpanded = true
        model.showPortraits(folderID: folder.persistentModelID)
        draftName = folder.name
        renamingFolder = folder
    }

    // MARK: - Upgrade-banner + quota

    private var upgradeBanner: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            HStack(spacing: DSSpacing.gap2) {
                Text(entitlement.isProActive ? "Pro plan" : "Starter plan")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.primary)
                Spacer(minLength: 0)
                if !entitlement.isProActive {
                    DSChip("Upgrade", type: .brand) { entitlement.requestUpgrade() }
                }
            }
            if !entitlement.quotaSummary.isEmpty {
                Text("\(entitlement.quotaSummary) images")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
        }
        .padding(DSSpacing.gap3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.Background.inset, in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
    }

    // MARK: - Gebruikersrij + menu

    private var userRow: some View {
        Button { showUserMenu.toggle() } label: {
            HStack(spacing: DSSpacing.gap2) {
                Circle()
                    .fill(DSColor.Background.neutralStronger)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(userInitial)
                            .dsTextStyle(.labelSmall)
                            .foregroundStyle(DSColor.Foreground.primary)
                    )
                Text(userDisplayName)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dsHoverHighlight(cornerRadius: DSRadius.lg)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showUserMenu, arrowEdge: .top) {
            userMenu
        }
    }

    private var userMenu: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            menuRow("Settings", icon: "gearshape") {
                showUserMenu = false
                model.isShowingSettings = true
            }
            menuRow("Manage backgrounds", icon: "photo.on.rectangle") {
                showUserMenu = false
                model.isShowingManageBackgrounds = true
            }
            if entitlement.isSignedIn {
                Divider().padding(.vertical, 2)
                menuRow("Sign out", icon: "rectangle.portrait.and.arrow.right", destructive: true) {
                    showUserMenu = false
                    entitlement.signOutAccount()
                }
            }
        }
        .padding(DSSpacing.gap1)
        .frame(width: 220)
    }

    private func menuRow(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: 18)
                Text(title).dsTextStyle(.labelBase)
                Spacer(minLength: 0)
            }
            .foregroundStyle(destructive ? DSColor.Signal.error : DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dsHoverHighlight(cornerRadius: DSRadius.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Afgeleide gebruikerslabels

    private var userDisplayName: String {
        guard let email = entitlement.accountEmail, !email.isEmpty else { return "Sign in" }
        return String(email.prefix(while: { $0 != "@" }))
    }

    private var userInitial: String {
        let name = userDisplayName
        return name == "Sign in" ? "?" : String(name.prefix(1)).uppercased()
    }
}

/// Eén navigatierij in de left-nav (icoon + label + selectie-highlight).
private struct LeftNavRow: View {
    let icon: Image
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(title)
                    .dsTextStyle(.labelBase)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? DSColor.Foreground.primary : DSColor.Foreground.subtle)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dsMotion(DSMotion.micro, value: hovering)
    }

    private var rowBackground: Color {
        if isSelected { return DSColor.Background.neutralStronger }
        if hovering { return DSColor.Background.neutral }
        return .clear
    }
}
