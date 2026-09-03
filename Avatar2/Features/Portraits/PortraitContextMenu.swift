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

    // E57.1: submenu's zijn `DSMenuSubmenu` (eigen child window naast de rij,
    // hover-intent + keyboard via de DS-menuboom) — geen eigen flyout-state.
    var body: some View {
        DSContextMenuPanel(minWidth: isBulk ? 270 : 200) {
            if isBulk {
                bulkRows
            } else {
                singleRows
            }
        }
    }

    private var isBulk: Bool {
        let ids = model.selectedPortraitIDs
        return ids.count >= 2 && ids.contains(portrait.persistentModelID)
    }

    @ViewBuilder private var singleRows: some View {
        DSMenuRow("Open", icon: "arrow.up.forward") {
            onDismiss(); model.openPortrait(portrait)
        }
        DSMenuSubmenu("Move to folder", icon: "folder", minWidth: 180) {
            moveRows(targets: [portrait])
        }
        // E50.5: het map-menu van de map waarin dit portret staat — dezelfde
        // acties als de map-rij in de left-nav (incl. Duplicate), bereikbaar
        // vanaf Home en Portraits zonder naar de sidebar te hoeven.
        if let folder = portrait.folder {
            DSMenuSubmenu("Folder “\(folder.name)”", icon: "folder.fill", minWidth: 200) {
                folderRows(folder)
            }
        }
        editSubmenu(targets: [portrait])
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
        DSMenuSubmenu("Move \(n) to folder", icon: "folder", minWidth: 180) {
            moveRows(targets: targets)
        }
        DSMenuRow("Match framing", icon: "square.resize", shortcut: "⌥⌘F") {
            onDismiss()
            PortraitSetActions.matchFraming(targets, undoManager: undoManager, reporter: model.setActionReporter)
        }
        editSubmenu(targets: targets)
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

    // MARK: - Edit ▸ (E57.2)

    /// Eén lopende Edit-batch tegelijk: dezelfde bron als de editor-chips
    /// (`workingContext.blocksOtherAIFeatures`) plus de set-actie-toast.
    private var editIsBusy: Bool {
        model.isSetActionBusy || entitlement.workingContext?.blocksOtherAIFeatures == true
    }

    /// Edit ▸ Boost resolution ▸ (On device / Online) — voor 1…N portretten.
    /// Thierry 2026-09-03: Boost ontbrak bij enkel-select in een map; i.p.v.
    /// een losse rij één Edit-tak waar Fill in body (57.3) en Apply effect
    /// (57.4) ook onder komen. Labels tellen mee bij bulk ("…on N").
    @ViewBuilder private func editSubmenu(targets: [Portrait2]) -> some View {
        let n = targets.count
        let suffix = n >= 2 ? " on \(n)" : ""
        // E57.5: reden bij de disabled-staat (native tooltip; de rij zelf
        // heeft geen DS-tooltip-slot).
        DSMenuSubmenu("Edit", icon: "wand.and.stars", disabled: editIsBusy, minWidth: 230) {
            DSMenuSubmenu("Boost resolution\(suffix)", icon: "arrow.up.left.and.arrow.down.right", minWidth: 230) {
                boostRows(targets: targets)
            }
            // E57.3: zelfde contract als de editor-tegel (E56) — alleen echt
            // afgesneden randen; zonder afgesneden rand een gratis no-op.
            DSMenuRow("Fill in body\(suffix)", icon: "figure.arms.open", shortcut: fillBodyLabel(count: n)) {
                onDismiss()
                PortraitSetActions.fillBody(
                    targets, entitlement: entitlement,
                    undoManager: undoManager, reporter: model.setActionReporter
                )
            }
            // E57.4: stijlen uit dezelfde lijst als het Effects-paneel.
            DSMenuSubmenu("Apply effect\(suffix)", icon: "sparkles", minWidth: 250) {
                effectRows(targets: targets)
            }
        }
        .help(editIsBusy ? "Wait for the current edit to finish" : "Boost resolution, fill in body or apply a style")
    }

    /// None · eigen effecten (Pro) · built-in stijlen. Label rechts: "Cached"
    /// als geen enkel portret hoeft te genereren, anders het credits-totaal
    /// voor de portretten die wél genereren (zonder Cloud-tier: "Cloud").
    @ViewBuilder private func effectRows(targets: [Portrait2]) -> some View {
        let list = EffectsModel.cachedEffectList(entitlement: entitlement)
        if targets.contains(where: { $0.effectActiveRaw != nil }) {
            DSMenuRow("None", icon: "circle.slash") {
                runEffect(.none, on: targets, list: list.builtin)
            }
            Divider().padding(.vertical, 2)
        }
        if !list.custom.isEmpty {
            ForEach(list.custom) { effect in
                DSMenuRow(
                    effect.label, icon: "sparkles",
                    shortcut: effectLabel(targets, choice: .custom(effect)),
                    accessory: { DSProChip() }
                ) {
                    runEffect(.custom(effect), on: targets, list: list.builtin)
                }
            }
            Divider().padding(.vertical, 2)
        }
        ForEach(list.builtin) { effect in
            DSMenuRow(
                effect.label, icon: effect.isDieCut ? "seal" : "paintbrush",
                shortcut: effectLabel(targets, choice: .builtin(effect))
            ) {
                runEffect(.builtin(effect), on: targets, list: list.builtin)
            }
        }
    }

    private func effectLabel(_ targets: [Portrait2], choice: PortraitSetActions.EffectChoice) -> String {
        let generating = PortraitSetActions.effectGenerationCount(targets, choice: choice)
        guard generating > 0 else { return "Cached" }
        guard PrivacyPreferences2.shared.allowsThirdPartyCloud else { return "Cloud" }
        let total = CreditMeter.credits(for: .generativeStandard) * generating
        return total == 1 ? "1 credit" : "\(total) credits"
    }

    private func runEffect(_ choice: PortraitSetActions.EffectChoice, on targets: [Portrait2], list: [RemoteEffect]) {
        onDismiss()
        PortraitSetActions.applyEffect(
            targets, choice: choice,
            isDieCut: { key in list.first { $0.key == key }?.isDieCut ?? false },
            model: model, entitlement: entitlement,
            undoManager: undoManager, reporter: model.setActionReporter
        )
    }

    /// Credits-totaal (2 per portret; alleen afgeschreven als er echt gevuld
    /// wordt); zonder Cloud-tier de neutrale "Cloud"-hint, zoals bij Boost.
    private func fillBodyLabel(count: Int) -> String {
        guard PrivacyPreferences2.shared.allowsThirdPartyCloud else { return "Cloud" }
        let total = CreditMeter.credits(for: .fillBody) * count
        return total == 1 ? "1 credit" : "\(total) credits"
    }

    /// Boost-modus kiezen. Online toont het totaal aan credits (3 per
    /// portret); zonder Cloud-tier de neutrale "Cloud"-hint — de gate vraagt
    /// dan zelf om de tier te verhogen (zoals in de editor).
    @ViewBuilder private func boostRows(targets: [Portrait2]) -> some View {
        let onlineLabel: String = {
            guard PrivacyPreferences2.shared.allowsThirdPartyCloud else { return "Sharper · Cloud" }
            let total = CreditMeter.credits(for: .upscaleHigh) * targets.count
            return "Best · \(total == 1 ? "1 credit" : "\(total) credits")"
        }()
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

    /// Map-acties van de map van dit portret (gedeeld `FolderDSContextMenu`);
    /// alleen de rijen — het submenu tekent zelf het paneel.
    private func folderRows(_ folder: Folder2) -> some View {
        FolderDSContextMenu(
            folder: folder,
            items: FolderSetScope.items(in: folder.portraits, folderID: nil),
            folders: folders,
            model: model,
            modelContext: modelContext,
            undoManager: undoManager,
            onDismiss: onDismiss
        ).rows
    }

    @ViewBuilder private func moveRows(targets: [Portrait2]) -> some View {
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
