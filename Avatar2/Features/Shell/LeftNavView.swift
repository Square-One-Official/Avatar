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
    /// Totale breedte van de sidebar-slot (kaart + leading inset).
    static var layoutWidth: CGFloat { width + edgeInset }
    /// Breedte van de vaste chrome-strook t.o.v. de vensterrand (leading inset + kaart).
    static var chromeRevealWidth: CGFloat { width + edgeInset }

    static let windowChromeHeight: CGFloat = 44

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // E50.1: map-brede acties (Select all/Align/Match/Export) werken op de
    // portretten van de map; undoManager voor de undo-groepen van Align/Match.
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \Folder2.createdAt, order: .forward) private var folders: [Folder2]
    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]

    /// Hoogte van de klikbare profielrij (zonder de omringende padding).
    private static let userRowHeight: CGFloat = 40

    @State private var showUserMenu = false
    @State private var renamingFolder: Folder2?
    @State private var isCreatingFolder = false
    @State private var draftName = ""
    /// De map waarboven nu een portret zweeft (drop-highlight). Eén tegelijk.
    @State private var dropTargetedFolderID: PersistentIdentifier?
    @State private var menuFolder: Folder2?
    @State private var menuAnchor: CGRect = .zero
    /// E46.1: map-delete vraagt eerst bevestiging (zelfde patroon als portret-delete).
    @State private var deletingFolder: Folder2?

    private static let contextMenuSpace = "leftNavContextMenu"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Placeholder onder de vaste venster-chrome (ShellSidebarChrome).
            Color.clear
                .frame(height: Self.windowChromeHeight)

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

                    // E35.2: Banners-bibliotheek (herbruikbare covers). Verborgen
                    // achter de feature-flag (release zonder banners).
                    if AppFeatureFlags.bannersEnabled {
                        LeftNavRow(
                            icon: Image(systemName: "rectangle.on.rectangle.angled"),
                            title: "Banners",
                            isSelected: model.section == .banners && !model.isShowingSettings
                        ) {
                            model.showBanners()
                        }
                    }
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
        // Inset kaart: dunne marge links + boven/onder via ShellView; rechts flush
        // op de content-kolom. macOS floating-panel hoekradius.
        .background(DSColor.Background.card)
        .clipShape(
            RoundedRectangle(cornerRadius: ShellMetrics.panelCornerRadius, style: .continuous)
        )
        .overlay {
            if showUserMenu {
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showUserMenu = false }
                    userMenu
                        .fixedSize()
                        .padding(.horizontal, DSSpacing.gap2)
                        .padding(.bottom, DSSpacing.gap2 + Self.userRowHeight + DSSpacing.gap2)
                        .transition(.dsScaleFade(anchor: .bottom, reduceMotion: reduceMotion))
                }
            }
            if menuFolder != nil {
                DSContextMenuOverlay(anchor: menuAnchor, onDismiss: { menuFolder = nil }) {
                    if let folder = menuFolder {
                        folderMenu(folder)
                    }
                }
            }
        }
        .coordinateSpace(name: Self.contextMenuSpace)
        .dsMotion(DSMotion.fast, value: showUserMenu)
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
        .alert("Create folder", isPresented: $isCreatingFolder) {
            TextField("Folder name", text: $draftName)
            Button("Create") { confirmCreateFolder() }
            Button("Cancel", role: .cancel) { isCreatingFolder = false }
        }
        // E46.1: delete met bevestiging (zelfde toon als portret-delete). De
        // delete-rule is `.nullify`, dus de portretten in de map blijven bestaan —
        // dat zegt de message expliciet.
        .confirmationDialog(
            "Delete this folder?",
            isPresented: Binding(
                get: { deletingFolder != nil },
                set: { if !$0 { deletingFolder = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let folder = deletingFolder {
                    if model.selectedFolderID == folder.persistentModelID {
                        model.selectedFolderID = nil
                    }
                    modelContext.delete(folder)
                }
                deletingFolder = nil
            }
            Button("Cancel", role: .cancel) { deletingFolder = nil }
        } message: {
            Text("Portraits in this folder are kept. This can't be undone.")
        }
    }

    // MARK: - Portraits (inklapbaar) + mappen

    private var portraitsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            LeftNavExpandableHeader(
                title: "Portraits",
                icon: "square.grid.2x2",
                isSelected: isPortraitsAllSelected,
                isExpanded: model.isPortraitsExpanded,
                onNavigate: { model.showPortraits(folderID: nil) },
                onToggleExpanded: { model.togglePortraitsExpanded() },
                onCreateFolder: { beginCreateFolder() }
            )

            if model.isPortraitsExpanded {
                ForEach(folders) { folder in
                    folderRow(folder)
                }
                if folders.isEmpty {
                    Text("No folders yet")
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .padding(.leading, LeftNavExpandableHeader.folderTextLeadingInset + LeftNavExpandableHeader.folderNestIndent)
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
        return LeftNavFolderRow(
            name: folder.name,
            isSelected: isSelected,
            isDropTargeted: isDropTargeted
        ) {
            model.showPortraits(folderID: folder.persistentModelID)
        }
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
        .contextMenuTrigger(in: .named(Self.contextMenuSpace)) { frame in
            menuFolder = folder
            menuAnchor = frame
        }
    }

    /// E50.1: rechtermuis-menu op een map-rij — map-brede set-acties (dezelfde
    /// `PortraitSetActions` als de handmatige multi-selectie, maar op ALLE
    /// portretten in de map) + de bestaande Rename/Delete.
    private func folderMenu(_ folder: Folder2) -> some View {
        let items = FolderSetScope.items(in: portraits, folderID: folder.persistentModelID)
        return DSContextMenuPanel(minWidth: 210) {
            DSMenuRow("Select all in folder", icon: "checkmark.circle", disabled: items.isEmpty) {
                menuFolder = nil
                // Eerst naar de map navigeren (wist de selectie), dán alles
                // selecteren — de gebruiker ZIET meteen wat er geselecteerd is.
                model.showPortraits(folderID: folder.persistentModelID)
                model.selectAllPortraits(items.map(\.persistentModelID))
            }
            DSMenuRow("Align set", icon: "align.horizontal.left", disabled: items.isEmpty) {
                menuFolder = nil
                PortraitSetActions.align(items, undoManager: undoManager) { model.setBusyMessage = $0 }
            }
            // Match lighting heeft ≥2 portretten nodig (referentie + minstens één
            // doel); referentie = het jongst bewerkte portret (bovenaan de lens).
            DSMenuRow("Match lighting", icon: "sun.max", disabled: items.count < 2) {
                menuFolder = nil
                guard let reference = FolderSetScope.matchLightingReference(items) else { return }
                PortraitSetActions.matchLighting(
                    items, reference: reference, undoManager: undoManager
                ) { model.setBusyMessage = $0 }
            }
            DSMenuRow("Export set", icon: "square.and.arrow.up.on.square", disabled: items.isEmpty) {
                menuFolder = nil
                PortraitSetActions.export(items, isPro: model.isPro) { model.setBusyMessage = $0 }
            }
            Divider().padding(.vertical, 2)
            DSMenuRow("Rename", icon: "pencil") {
                menuFolder = nil
                draftName = folder.name
                renamingFolder = folder
            }
            Divider().padding(.vertical, 2)
            DSMenuRow("Delete", icon: "trash", destructive: true) {
                menuFolder = nil
                deletingFolder = folder
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

    private func beginCreateFolder() {
        draftName = ""
        isCreatingFolder = true
    }

    private func confirmCreateFolder() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let n = folders.count + 1
        let folder = Folder2(name: name, order: n)
        modelContext.insert(folder)
        model.isPortraitsExpanded = true
        model.showPortraits(folderID: folder.persistentModelID)
        isCreatingFolder = false
    }

    // MARK: - Upgrade-banner + quota

    private var upgradeBanner: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            HStack(spacing: DSSpacing.gap2) {
                Text(entitlement.isProActive ? "Credits" : "Starter plan")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.primary)
                Spacer(minLength: 0)
                if entitlement.isProActive {
                    DSChip("Add credits", type: .brand) { entitlement.requestUpgrade() }
                } else {
                    DSChip("Upgrade", type: .brand) { entitlement.requestUpgrade() }
                }
            }
            if !upgradeBannerQuotaText.isEmpty {
                Text(upgradeBannerQuotaText)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
        }
        .padding(DSSpacing.gap3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.Background.inset, in: RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
    }

    /// Pro: credit-balans (niet "images"). Free: portrait-imports over lifetime-cap.
    private var upgradeBannerQuotaText: String {
        let summary = entitlement.quotaSummary
        guard !summary.isEmpty else { return "" }
        if entitlement.isProActive {
            return summary.hasSuffix("credits") ? summary : "\(summary) credits"
        }
        return "\(summary) images"
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
            .frame(height: Self.userRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dsHoverHighlight(cornerRadius: DSRadius.lg)
        }
        .buttonStyle(.plain)
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
        .dsPanelSurface(cornerRadius: DSRadius.lg)
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

/// Inklapbare sectiekop (Granola-stijl): icoon standaard, chevron op row-hover,
/// aparte hit areas voor navigeren / uitklappen / map aanmaken.
private struct LeftNavExpandableHeader: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let isExpanded: Bool
    let onNavigate: () -> Void
    let onToggleExpanded: () -> Void
    let onCreateFolder: () -> Void

    @State private var rowHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Vaste breedte links zodat label niet verschuift bij icon ↔ chevron.
    /// Zelfde 18 pt als `LeftNavRow`-iconen → label kolom lijn-ligt met Home/Banners.
    private static let leadingSlotSize: CGFloat = 18

    /// Leading inset van de Portraits-titel t.o.v. de rij (padding + slot + gap).
    static var folderTextLeadingInset: CGFloat {
        DSSpacing.gap2 + leadingSlotSize + DSSpacing.gap2
    }

    /// Extra inspringing zodat map-rijen visueel onder Portraits vallen.
    static let folderNestIndent: CGFloat = DSSpacing.gap3

    /// Leading padding voor een map-rij (icoon-kolom).
    static var folderRowLeadingInset: CGFloat {
        folderTextLeadingInset + folderNestIndent - 16 - DSSpacing.gap2
    }

    var body: some View {
        HStack(spacing: DSSpacing.gap2) {
            leadingSlot

            Button(action: onNavigate) {
                Text(title)
                    .dsTextStyle(.labelBase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onCreateFolder) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHoverHighlight(cornerRadius: DSRadius.md)
            .help("Create folder")
        }
        .foregroundStyle(isSelected ? DSColor.Foreground.primary : DSColor.Foreground.subtle)
        .padding(.horizontal, DSSpacing.gap2)
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        .contentShape(Rectangle())
        .onHover { rowHovering = $0 }
        .dsMotion(DSMotion.micro, value: rowHovering)
    }

    @ViewBuilder
    private var leadingSlot: some View {
        ZStack {
            Group {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.leadingSlotSize, height: Self.leadingSlotSize)

                Button(action: onNavigate) {
                    Color.clear
                        .frame(width: Self.leadingSlotSize, height: Self.leadingSlotSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .opacity(rowHovering ? 0 : 1)
            .scaleEffect(rowHovering ? 0.94 : 1, anchor: .center)
            .allowsHitTesting(!rowHovering)

            Button(action: onToggleExpanded) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
                    .frame(width: Self.leadingSlotSize, height: Self.leadingSlotSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHoverHighlight(cornerRadius: DSRadius.md)
            .opacity(rowHovering ? 1 : 0)
            .scaleEffect(rowHovering ? 1 : 0.94, anchor: .center)
            .allowsHitTesting(rowHovering)
        }
        .frame(width: Self.leadingSlotSize, height: Self.leadingSlotSize)
        .animation(reduceMotion ? nil : DSMotion.micro, value: rowHovering)
    }

    private var rowBackground: Color {
        if isSelected { return DSColor.Background.neutralStronger }
        if rowHovering { return DSColor.Background.neutral }
        return .clear
    }
}

/// Eén map-rij onder Portraits (indent + hover/selectie/drop-highlight).
private struct LeftNavFolderRow: View {
    let name: String
    let isSelected: Bool
    let isDropTargeted: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 16)
                Text(name)
                    .dsTextStyle(.labelBase)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected || isDropTargeted ? DSColor.Foreground.primary : DSColor.Foreground.subtle)
            .padding(.leading, LeftNavExpandableHeader.folderRowLeadingInset)
            .padding(.trailing, DSSpacing.gap2)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                        .strokeBorder(DSColor.Action.primary, lineWidth: DSBorderWidth.medium)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dsMotion(DSMotion.micro, value: hovering || isDropTargeted)
    }

    private var rowBackground: Color {
        if isDropTargeted { return DSColor.Action.primary.opacity(0.18) }
        if isSelected { return DSColor.Background.neutralStronger }
        if hovering { return DSColor.Background.neutral }
        return .clear
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
