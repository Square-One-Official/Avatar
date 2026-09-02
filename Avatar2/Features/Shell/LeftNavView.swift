// PoC (left-nav): Granola-stijl linker navigatie — de enige sidebar (de oude
// rechter set-sidebar is verdwenen). Bovenin een subtiele inklap-toggle náást
// de traffic-lights; daaronder Home (overzicht) en een INKLAPBARE Portraits-
// sectie die de mappen toont (+ een plus om een map te maken, rechtermuis om te
// hernoemen/verwijderen). Onderin de upgrade-banner + quota en een klikbare
// gebruikersrij: hoofdknop = sign-in (uitgelogd) of menu, chevron = menu
// (Settings / Manage backgrounds / Sign out). Net-nieuw scherm
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

    @State private var dropTargetedFolderID: PersistentIdentifier?
    /// Klik buiten accountrij + menu (waar dan ook in het venster) sluit het menu.
    @State private var userMenuClickScope = DSOutsideClickScope()
    @FocusState private var userRowFocused: Bool
    @State private var userRowHovering = false

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
        // op de content-kolom. Eén clipShape op de hele kaart — bovenhoeken komen
        // niet uit een aparte overlay (ShellSidebarChrome), dat patroon brak telkens.
        .background(DSColor.Background.card)
        .clipShape(
            RoundedRectangle(cornerRadius: ShellMetrics.panelCornerRadius, style: .continuous)
        )
        .overlay {
            if model.presentation.leftNavUserMenuOpen {
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { model.presentation.leftNavUserMenuOpen = false }
                    userMenu
                        .dsDismissOnOutsideClick(userMenuClickScope, isActive: true) {
                            model.presentation.leftNavUserMenuOpen = false
                        }
                        .fixedSize()
                        .padding(.horizontal, DSSpacing.gap2)
                        .padding(.bottom, DSSpacing.gap2 + Self.userRowHeight + DSSpacing.gap2)
                        .transition(.dsScaleFade(anchor: .bottom, reduceMotion: reduceMotion))
                }
            }
        }
        .background {
            if model.presentation.leftNavUserMenuOpen {
                Button("Close account menu") {
                    model.presentation.leftNavUserMenuOpen = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
        .onChange(of: model.presentation.leftNavUserMenuOpen) { _, open in
            if !open { userRowFocused = true }
        }
        .coordinateSpace(name: Self.contextMenuSpace)
        .dsMotion(DSMotion.fast, value: model.presentation.leftNavUserMenuOpen)
        .task { await entitlement.refresh() }
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
                        .foregroundStyle(DSColor.Foreground.subtle)
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
            model.presentation.openFolderContextMenu(
                folderID: folder.persistentModelID,
                anchor: frame
            )
        }
    }

    private func beginCreateFolder() {
        model.presentation.alert = .createFolder(draft: "")
    }

    /// Verplaats de gesleepte portretten naar `folder` (haalt het echte Portrait2
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
                    .foregroundStyle(DSColor.Foreground.subtle)
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

    /// Twee hit areas, zoals de Portraits-kop: de hoofdknop (avatar + naam)
    /// start sign-in wanneer niemand is ingelogd en opent anders het menu; de
    /// chevron rechts opent altijd het accountmenu.
    private var userRow: some View {
        HStack(spacing: DSSpacing.gap2) {
            Button {
                if entitlement.isSignedIn {
                    model.presentation.leftNavUserMenuOpen.toggle()
                } else {
                    model.presentation.leftNavUserMenuOpen = false
                    entitlement.presentSignIn()
                }
            } label: {
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
                        .help(userDisplayName)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.userRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
            .accessibilityLabel(userDisplayName)
            .accessibilityHint(entitlement.isSignedIn ? "Account menu" : "Sign in")

            Button { model.presentation.leftNavUserMenuOpen.toggle() } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: DSIconSize.xs, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($userRowFocused)
            .dsFocusEffectDisabled()
            .dsHoverHighlight(cornerRadius: DSRadius.md)
            .help("Account menu")
            .accessibilityLabel("Account menu")
        }
        .padding(.horizontal, DSSpacing.gap2)
        .frame(height: Self.userRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(userRowBackground, in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        .contentShape(Rectangle())
        .onHover { userRowHovering = $0 }
        .dsMotion(DSMotion.micro, value: userRowHovering)
        .dsOutsideClickInside(userMenuClickScope)
    }

    private var userRowBackground: Color {
        userRowHovering ? DSColor.Background.neutral : .clear
    }

    private var userMenu: some View {
        DSContextMenuPanel(minWidth: 220) {
            DSMenuRow("Settings", icon: "gearshape") {
                model.presentation.leftNavUserMenuOpen = false
                model.isShowingSettings = true
            }
            DSMenuRow("Manage backgrounds", icon: "photo.on.rectangle") {
                model.presentation.leftNavUserMenuOpen = false
                model.isShowingManageBackgrounds = true
            }
            if entitlement.isSignedIn {
                Divider().padding(.vertical, 2)
                DSMenuRow("Sign out", icon: "rectangle.portrait.and.arrow.right", destructive: true) {
                    model.presentation.leftNavUserMenuOpen = false
                    entitlement.signOutAccount()
                }
            }
        }
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
    @FocusState private var chevronFocused: Bool

    private var chevronRevealed: Bool { rowHovering || chevronFocused }

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
            .dsFocusEffectDisabled()
            .accessibilityAction(named: isExpanded ? "Collapse folders" : "Expand folders") {
                onToggleExpanded()
            }

            Button(action: onCreateFolder) {
                Image(systemName: "plus")
                    .font(.system(size: DSIconSize.sm, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
            .dsHoverHighlight(cornerRadius: DSRadius.md)
            .help("Create folder")
            .accessibilityLabel("Create folder")
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
                .dsFocusEffectDisabled()
            }
            .opacity(chevronRevealed ? 0 : 1)
            .scaleEffect(chevronRevealed ? 0.94 : 1, anchor: .center)
            .allowsHitTesting(!chevronRevealed)

            Button(action: onToggleExpanded) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: DSIconSize.xs, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .frame(width: Self.leadingSlotSize, height: Self.leadingSlotSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
            .dsHoverHighlight(cornerRadius: DSRadius.md)
            .focused($chevronFocused)
            .dsFocusEffectDisabled()
            .opacity(chevronRevealed ? 1 : 0)
            .scaleEffect(chevronRevealed ? 1 : 0.94, anchor: .center)
            .allowsHitTesting(chevronRevealed)
            .accessibilityLabel(isExpanded ? "Collapse folders" : "Expand folders")
            .help(isExpanded ? "Collapse folders" : "Expand folders")
        }
        .frame(width: Self.leadingSlotSize, height: Self.leadingSlotSize)
        .dsMotion(DSMotion.micro, value: chevronRevealed)
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
                    .font(.system(size: DSIconSize.sm, weight: .regular))
                    .frame(width: 16)
                Text(name)
                    .dsTextStyle(.labelBase)
                    .lineLimit(1)
                    .help(name)
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
                        .strokeBorder(DSColor.Action.primaryForeground, lineWidth: DSBorderWidth.medium)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
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
        .dsFocusEffectDisabled()
        .onHover { hovering = $0 }
        .dsMotion(DSMotion.micro, value: hovering)
    }

    private var rowBackground: Color {
        if isSelected { return DSColor.Background.neutralStronger }
        if hovering { return DSColor.Background.neutral }
        return .clear
    }
}
