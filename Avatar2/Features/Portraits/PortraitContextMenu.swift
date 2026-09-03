// Gedeeld rechtermuis-menu voor portret-tegels (Home + Portraits-grid).
// DS-paneel i.p.v. native `.contextMenu`. Toont enkel-item-acties, of bulk-acties
// zodra er ≥2 geselecteerd zijn en op een geselecteerd item wordt geklikt
// (Finder-stijl).

import AvatarKit
import AvatarUI
import SwiftData
import SwiftUI

/// Naam bewaard voor bestaande `.coordinateSpace`-call sites; ankers zelf
/// worden in SwiftUI `.global` gemeten (zie `contextMenuTrigger`).
enum PortraitContextMenuSpace {
    static let name = "portraitContextMenu"
    static var coordinateSpace: CoordinateSpace { .named(name) }
}

// MARK: - Zwevend menu (DS)

struct PortraitDSContextMenu: View {
    let portrait: Portrait2
    let model: ShellModel
    /// Voor de bulk-Boost (privacy-/sign-in-/credits-gate + backend).
    let entitlement: EntitlementModel
    let folders: [Folder2]
    let selectedTargets: () -> [Portrait2]
    /// Voor Duplicate in de "Folder …"-flyout (nieuwe map + portretten invoegen).
    let modelContext: ModelContext
    let undoManager: UndoManager?
    let onDismiss: () -> Void
    let onRequestDelete: ([Portrait2]) -> Void
    let onRequestNewFolder: ([Portrait2]) -> Void
    let onRequestSetBackground: ([Portrait2]) -> Void

    @State private var moveFlyoutOpen = false
    @State private var boostFlyoutOpen = false
    @State private var folderFlyoutOpen = false

    var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.gap1) {
            DSContextMenuPanel(minWidth: isBulk ? 270 : 200) {
                if isBulk {
                    bulkRows
                } else {
                    singleRows
                }
            }
            if moveFlyoutOpen {
                moveFlyout
            } else if boostFlyoutOpen {
                boostFlyout
            } else if folderFlyoutOpen, let folder = portrait.folder {
                folderFlyout(folder)
            }
        }
    }

    /// Eén flyout tegelijk (Move ↔ Boost ↔ Folder).
    private func toggleMoveFlyout() {
        moveFlyoutOpen.toggle()
        if moveFlyoutOpen { boostFlyoutOpen = false; folderFlyoutOpen = false }
    }

    private func toggleBoostFlyout() {
        boostFlyoutOpen.toggle()
        if boostFlyoutOpen { moveFlyoutOpen = false; folderFlyoutOpen = false }
    }

    private func toggleFolderFlyout() {
        folderFlyoutOpen.toggle()
        if folderFlyoutOpen { moveFlyoutOpen = false; boostFlyoutOpen = false }
    }

    private var isBulk: Bool {
        let ids = model.selectedPortraitIDs
        return ids.count >= 2 && ids.contains(portrait.persistentModelID)
    }

    @ViewBuilder private var singleRows: some View {
        DSMenuRow("Open", icon: "arrow.up.forward") {
            onDismiss(); model.openPortrait(portrait)
        }
        DSMenuRow("Move to folder", icon: "folder", showsChevron: true) {
            toggleMoveFlyout()
        }
        // E50.5: het map-menu van de map waarin dit portret staat — dezelfde
        // acties als de map-rij in de left-nav (incl. Duplicate), bereikbaar
        // vanaf Home en Portraits zonder naar de sidebar te hoeven.
        if let folder = portrait.folder {
            DSMenuRow("Folder “\(folder.name)”", icon: "folder.fill", showsChevron: true) {
                toggleFolderFlyout()
            }
        }
        DSMenuRow("Export…", icon: "square.and.arrow.up") {
            onDismiss(); model.select(portrait); model.exportCurrentPortrait()
        }
        // E50.3: de map-default achtergrond alsnog toepassen (portret van vóór
        // de default, of later een andere achtergrond gekregen).
        if PortraitSetActions.canUseFolderBackground(portrait) {
            DSMenuRow("Use folder background", icon: "photo.on.rectangle") {
                onDismiss()
                PortraitSetActions.useFolderBackground([portrait], undoManager: undoManager, reporter: model.setActionReporter)
            }
        }
        // E50.3: de terugweg voor Match lighting vanuit het raster — gaat mee
        // achter de flag (Thierry 2026-09-02: "Reset adjustments can go too").
        if AppFeatureFlags.matchLightingEnabled, !portrait.adjust.isNeutral {
            DSMenuRow("Reset adjustments", icon: "slider.horizontal.3") {
                onDismiss()
                PortraitSetActions.resetAdjust([portrait], undoManager: undoManager, reporter: model.setActionReporter)
            }
        }
        Divider().padding(.vertical, 2)
        DSMenuRow("Delete", icon: "trash", destructive: true) {
            onDismiss(); onRequestDelete([portrait])
        }
    }

    @ViewBuilder private var bulkRows: some View {
        let targets = selectedTargets()
        let n = targets.count
        DSMenuRow("Export \(n) portraits…", icon: "square.and.arrow.up.on.square") {
            onDismiss()
            PortraitSetActions.export(targets, isPro: model.isPro, reporter: model.setActionReporter)
        }
        DSMenuRow("Move \(n) to folder", icon: "folder", showsChevron: true) {
            toggleMoveFlyout()
        }
        DSMenuRow("Match framing", icon: "square.resize", shortcut: "⌥⌘F") {
            onDismiss()
            PortraitSetActions.matchFraming(targets, undoManager: undoManager, reporter: model.setActionReporter)
        }
        // Aanvulling Thierry 2026-09-02: Boost ook op een map-selectie. Zelfde
        // twee modi als de editor-chip (E41.2/E41.5), via een flyout.
        DSMenuRow("Boost resolution on \(n)", icon: "arrow.up.left.and.arrow.down.right", showsChevron: true) {
            toggleBoostFlyout()
        }
        // E50.3: "Match lighting" kiest zelf het doel (het patroon van de set of
        // het best belichte portret); "…to this one" is de expliciete override
        // met de aangeklikte tegel als referentie. Geschrapt (flag) — zie
        // `AppFeatureFlags.matchLightingEnabled`.
        if AppFeatureFlags.matchLightingEnabled {
            DSMenuRow("Match lighting", icon: "sun.max", shortcut: "⌥⌘L") {
                onDismiss()
                PortraitSetActions.matchLighting(targets, undoManager: undoManager, reporter: model.setActionReporter)
            }
            DSMenuRow("Match lighting to this one", icon: "sun.max.circle") {
                onDismiss()
                PortraitSetActions.matchLighting(
                    targets, reference: portrait, undoManager: undoManager, reporter: model.setActionReporter
                )
            }
        }
        DSMenuRow("Set background…", icon: "photo", shortcut: "⇧⌘B") {
            onRequestSetBackground(targets)
        }
        let folderable = targets.filter(PortraitSetActions.canUseFolderBackground).count
        if folderable > 0 {
            DSMenuRow("Use folder background on \(folderable)", icon: "photo.on.rectangle") {
                onDismiss()
                PortraitSetActions.useFolderBackground(targets, undoManager: undoManager, reporter: model.setActionReporter)
            }
        }
        if AppFeatureFlags.matchLightingEnabled, targets.contains(where: { !$0.adjust.isNeutral }) {
            DSMenuRow("Reset adjustments on \(n)", icon: "slider.horizontal.3") {
                onDismiss()
                PortraitSetActions.resetAdjust(targets, undoManager: undoManager, reporter: model.setActionReporter)
            }
        }
        Divider().padding(.vertical, 2)
        DSMenuRow("Delete \(n)", icon: "trash", destructive: true) {
            onDismiss(); onRequestDelete(targets)
        }
    }

    /// Boost-modus kiezen voor de hele selectie. Online toont het totaal aan
    /// credits (3 per portret); zonder Cloud-tier de neutrale "Cloud"-hint —
    /// de gate vraagt dan zelf om de tier te verhogen (zoals in de editor).
    private var boostFlyout: some View {
        let targets = selectedTargets()
        let onlineLabel: String = {
            guard PrivacyPreferences2.shared.allowsThirdPartyCloud else { return "Sharper · Cloud" }
            let total = CreditMeter.credits(for: .upscaleHigh) * targets.count
            return "Best · \(total == 1 ? "1 credit" : "\(total) credits")"
        }()
        return DSContextMenuPanel(minWidth: 230) {
            DSMenuRow("On device", icon: "desktopcomputer", shortcut: "Free") {
                onDismiss()
                PortraitSetActions.boostResolution(
                    targets, mode: .local, entitlement: entitlement,
                    undoManager: undoManager, reporter: model.setActionReporter
                )
            }
            DSMenuRow("Online", icon: "cloud", shortcut: onlineLabel) {
                onDismiss()
                PortraitSetActions.boostResolution(
                    targets, mode: .online, entitlement: entitlement,
                    undoManager: undoManager, reporter: model.setActionReporter
                )
            }
        }
    }

    /// Map-acties van de map van dit portret (gedeeld `FolderDSContextMenu`).
    private func folderFlyout(_ folder: Folder2) -> some View {
        FolderDSContextMenu(
            folder: folder,
            items: FolderSetScope.items(in: folder.portraits, folderID: nil),
            folders: folders,
            model: model,
            modelContext: modelContext,
            undoManager: undoManager,
            onDismiss: onDismiss
        )
    }

    private var moveFlyout: some View {
        let targets = isBulk ? selectedTargets() : [portrait]
        return DSContextMenuPanel(minWidth: 180) {
            DSMenuRow("Unfiled", icon: "tray") {
                onDismiss()
                for p in targets { p.folder = nil }
            }
            if !folders.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(folders) { folder in
                    DSMenuRow(folder.name, icon: "folder") {
                        onDismiss()
                        for p in targets { p.folder = folder }
                    }
                }
            }
            Divider().padding(.vertical, 2)
            // E36.5 (audit-B5): geen stille "Untitled folder N" meer — vraag
            // altijd een naam (zelfde DSDialog als de left-nav-flow); de overlay
            // toont de prompt en maakt de map pas na bevestiging.
            DSMenuRow("New folder…", icon: "folder.badge.plus") {
                onDismiss()
                onRequestNewFolder(targets)
            }
        }
    }
}

// MARK: - View extensions

extension View {
    func portraitContextMenuTrigger(
        portrait: Portrait2,
        model: ShellModel,
        scope: ContextMenuScope
    ) -> some View {
        contextMenuTrigger(in: PortraitContextMenuSpace.coordinateSpace) { frame in
            model.preparePortraitContextMenu(on: portrait)
            model.presentation.openPortraitContextMenu(
                portraitID: portrait.persistentModelID,
                anchor: frame,
                scope: scope
            )
        }
    }
}
