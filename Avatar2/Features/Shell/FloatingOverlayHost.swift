// E53.7 — centrale overlay-host op ShellView. Rendert contextmenu's,
// preview-kiezers en store-gedreven alerts/confirms zodat ze open blijven
// bij tab-/vensterwissel.

import AvatarUI
import SwiftData
import SwiftUI

struct FloatingOverlayHost: View {
    @Bindable var model: ShellModel
    let entitlement: EntitlementModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \Folder2.createdAt, order: .forward) private var folders: [Folder2]
    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
    @Query(sort: \BannerDoc.updatedAt, order: .reverse) private var bannerDocs: [BannerDoc]

    var body: some View {
        ZStack {
            portraitContextLayer
            selectionBackgroundPickerLayer
            leftNavFolderMenuLayer
            bannerGalleryMenuLayer
        }
        // Vul de hele overlay: zonder menu's is de ZStack 0×0, waardoor de
        // modal-overlays hieronder een 0-proposal krijgen — de dim-backdrop
        // (`Color.black.opacity`) wordt dan door de ZStack-plaatsing op de
        // dialog-bounds gezet i.p.v. op het venster (hard grijs kader rond de
        // kaart, geen dimming). Een leeg frame vangt geen clicks.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusedSceneValue(\.portraitSet, portraitSetAction)
        .background { escapeBackgroundPicker }
        .overlay { coloriseAlreadyColourDialog }
        .overlay { namePromptDialog }
        .dsMotion(DSMotion.fast, value: model.presentation.confirm == .coloriseAlreadyColour)
        .dsMotion(DSMotion.fast, value: model.presentation.alert)
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(
                get: { showsDestructiveConfirm },
                set: { if !$0 {
                    if showsDestructiveConfirm { model.presentation.confirm = nil }
                } }
            ),
            titleVisibility: .visible
        ) {
            confirmButtons
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: - Portrait context menus

    @ViewBuilder private var portraitContextLayer: some View {
        if let request = model.presentation.portraitContextMenu,
           let portraitID = request.portraitID,
           let portrait = portraits.first(where: { $0.persistentModelID == portraitID }) {
            DSContextMenuOverlay(anchor: request.anchor, onDismiss: {
                model.presentation.dismissPortraitContextMenu()
            }) {
                PortraitDSContextMenu(
                    portrait: portrait,
                    model: model,
                    entitlement: entitlement,
                    folders: folders,
                    selectedTargets: { portraits.filter { model.isPortraitSelected($0) } },
                    modelContext: modelContext,
                    undoManager: undoManager,
                    onDismiss: { model.presentation.dismissPortraitContextMenu() },
                    onRequestDelete: { targets in
                        model.presentation.dismissPortraitContextMenu()
                        model.presentation.confirm = .deletePortraits(
                            ids: targets.map(\.persistentModelID)
                        )
                    },
                    onRequestNewFolder: { targets in
                        model.presentation.dismissPortraitContextMenu()
                        model.presentation.alert = .createFolderForPortraits(
                            targetIDs: targets.map(\.persistentModelID),
                            draft: ""
                        )
                    },
                    onRequestSetBackground: { _ in
                        model.presentation.openSelectionBackgroundPicker(anchor: request.anchor)
                    }
                )
            }
        }
    }

    // MARK: - Selection background picker

    /// Groot paneel op een klik-anker: blijft binnen het venster (`.window`),
    /// anders hangt 'ie bij een klik rechtsonder half buiten de app. Kiezen
    /// sluit 'm — de "klaar"-toast (met Undo) landt rechtsonder, precies waar
    /// het paneel anders staat. `.panel`: overleeft een vensterwissel en kan
    /// key worden (hex-/zoek-/promptveld). Een eigen kleur gaat pas bij
    /// "Add colour" naar de selectie — live meebewegen zou elke drag-stap als
    /// een aparte set-actie (toast + undo-groep) afvuren én het paneel sluiten.
    @ViewBuilder private var selectionBackgroundPickerLayer: some View {
        if model.presentation.selectionBackgroundPickerOpen {
            let targets = portraits.filter { model.isPortraitSelected($0) }
            DSContextMenuOverlay(
                anchor: model.presentation.selectionBackgroundPickerAnchor,
                bounds: .window,
                kind: .panel,
                onDismiss: { model.presentation.closeSelectionBackgroundPicker() },
                menuWidth: 460,
                menuHeight: 480
            ) {
                BackgroundPanel(
                    portrait: targets.first,
                    onApply: { background in
                        model.presentation.closeSelectionBackgroundPicker()
                        PortraitSetActions.setBackground(
                            targets, background, undoManager: undoManager,
                            reporter: model.setActionReporter
                        )
                    },
                    appliesColorLive: false,
                    presentation: model.presentation,
                    entitlement: entitlement
                )
                .padding(DSSpacing.gap4)
                .frame(width: 440)
                .fixedSize(horizontal: false, vertical: true)
                .dsPanelSurface(cornerRadius: DSRadius.xl4)
            }
        }
    }

    private var escapeBackgroundPicker: some View {
        Button("") { model.presentation.closeSelectionBackgroundPicker() }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .disabled(!model.presentation.selectionBackgroundPickerOpen)
    }

    private var selectedPortraits: [Portrait2] {
        portraits.filter { model.isPortraitSelected($0) }
    }

    private var portraitSetAction: PortraitSetAction {
        PortraitSetAction(
            selectedCount: model.selectedPortraitIDs.count,
            matchFraming: {
                PortraitSetActions.matchFraming(
                    selectedPortraits, undoManager: undoManager, reporter: model.setActionReporter
                )
            },
            matchLighting: {
                PortraitSetActions.matchLighting(
                    selectedPortraits, undoManager: undoManager, reporter: model.setActionReporter
                )
            },
            setBackground: {
                let anchor = model.presentation.portraitContextMenu?.anchor
                    ?? model.presentation.selectionBackgroundPickerAnchor
                model.presentation.openSelectionBackgroundPicker(anchor: anchor)
            },
            canResetAdjust: selectedPortraits.contains { !$0.adjust.isNeutral },
            resetAdjust: {
                PortraitSetActions.resetAdjust(
                    selectedPortraits, undoManager: undoManager, reporter: model.setActionReporter
                )
            }
        )
    }

    // MARK: - Left nav folder menu

    @ViewBuilder private var leftNavFolderMenuLayer: some View {
        if let request = model.presentation.leftNavFolderMenu,
           let folderID = request.folderID,
           let folder = folders.first(where: { $0.persistentModelID == folderID }) {
            let items = FolderSetScope.items(in: portraits, folderID: folderID)
            DSContextMenuOverlay(anchor: request.anchor, onDismiss: {
                model.presentation.leftNavFolderMenu = nil
            }) {
                // Gedeeld map-menu (ook in de Portraits-header en het tegel-menu).
                FolderDSContextMenu(
                    folder: folder,
                    items: items,
                    folders: folders,
                    model: model,
                    modelContext: modelContext,
                    undoManager: undoManager,
                    onDismiss: { model.presentation.leftNavFolderMenu = nil }
                )
            }
        }
    }

    // MARK: - Banner gallery menu

    @ViewBuilder private var bannerGalleryMenuLayer: some View {
        if let request = model.presentation.bannerGalleryMenu,
           let bannerID = request.bannerID,
           let banner = bannerDocs.first(where: { $0.persistentModelID == bannerID }) {
            DSContextMenuOverlay(anchor: request.anchor, onDismiss: {
                model.presentation.bannerGalleryMenu = nil
            }) {
                BannerGalleryContextMenu(
                    banner: banner,
                    model: model,
                    onDismiss: { model.presentation.bannerGalleryMenu = nil },
                    onRename: {
                        model.presentation.bannerGalleryMenu = nil
                        model.presentation.alert = .renameBanner(bannerID: bannerID, draft: banner.name)
                    },
                    onDuplicate: {
                        model.presentation.bannerGalleryMenu = nil
                        duplicateBanner(banner)
                    },
                    onDelete: {
                        model.presentation.bannerGalleryMenu = nil
                        model.presentation.confirm = .deleteBanner(bannerID: bannerID)
                    }
                )
            }
        }
    }

    // MARK: - Confirms

    private func duplicateBanner(_ banner: BannerDoc) {
        let base = banner.name.isEmpty ? "Untitled banner" : banner.name
        let copy = BannerDoc(
            name: "\(base) copy",
            canvasSize: banner.canvasSize,
            layers: banner.layers,
            fillImageData: banner.fillImageData,
            logoImageData: banner.logoImageData,
            previewImageData: banner.previewImageData
        )
        modelContext.insert(copy)
    }

    // MARK: - Name prompt (DSDialog, geen systeem-alert)

    @ViewBuilder
    private var namePromptDialog: some View {
        if let alert = model.presentation.alert {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                DSDialog(
                    title: alert.title,
                    confirmLabel: alert.confirmLabel,
                    confirmEnabled: !trimmedAlertDraft.isEmpty,
                    onConfirm: { confirmNamePrompt(alert) },
                    onDismiss: { dismissNamePrompt() }
                ) {
                    DSTextField(
                        placeholder: alert.fieldPlaceholder,
                        autofocus: true,
                        text: Binding(
                            get: { model.presentation.alertDraft },
                            set: { model.presentation.alertDraft = $0 }
                        )
                    )
                    .onSubmit { confirmNamePrompt(alert) }
                }
                Button("Cancel") { dismissNamePrompt() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .accessibilityAddTraits(.isModal)
        }
    }

    private var trimmedAlertDraft: String {
        model.presentation.alertDraft.trimmingCharacters(in: .whitespaces)
    }

    private func dismissNamePrompt() {
        model.presentation.alert = nil
    }

    private func confirmNamePrompt(_ alert: PresentationAlert) {
        guard model.presentation.alert != nil else { return }
        let name = trimmedAlertDraft
        guard !name.isEmpty else { return }
        switch alert {
        case .renameFolder(let folderID, _):
            guard let folder = folders.first(where: { $0.persistentModelID == folderID }) else {
                dismissNamePrompt()
                return
            }
            folder.name = name
        case .createFolder:
            let folder = Folder2(name: name)
            modelContext.insert(folder)
            model.isPortraitsExpanded = true
            model.showPortraits(folderID: folder.persistentModelID)
        case .renameBanner(let bannerID, _):
            guard let banner = bannerDocs.first(where: { $0.persistentModelID == bannerID }) else {
                dismissNamePrompt()
                return
            }
            banner.name = name
        case .createFolderForPortraits(let targetIDs, _):
            let folder = Folder2(name: name)
            modelContext.insert(folder)
            for id in targetIDs {
                if let p = portraits.first(where: { $0.persistentModelID == id }) {
                    p.folder = folder
                }
            }
            model.isPortraitsExpanded = true
            model.showPortraits(folderID: folder.persistentModelID)
        }
        dismissNamePrompt()
    }

    // MARK: - Colorise already in colour

    @ViewBuilder
    private var coloriseAlreadyColourDialog: some View {
        if model.presentation.confirm == .coloriseAlreadyColour {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { model.presentation.dismissColoriseAlreadyColour() }
                DSMessageSheet(
                    title: ColoriseAlreadyColourCopy.title,
                    body: ColoriseAlreadyColourCopy.message,
                    ctaLabel: ColoriseAlreadyColourCopy.confirm,
                    onCTA: { model.presentation.confirmColoriseAlreadyColour() },
                    onDismiss: { model.presentation.dismissColoriseAlreadyColour() }
                )
            }
        }
    }

    // MARK: - Confirms

    /// Destructieve confirms (delete) gaan via confirmationDialog; Colorise
    /// gebruikt `DSMessageSheet` en naam-prompts `DSDialog` (geen systeem-alert).
    private var showsDestructiveConfirm: Bool {
        switch model.presentation.confirm {
        case .deleteAccount, .deletePortraits, .deleteFolder, .deleteBanner: true
        case .coloriseAlreadyColour, nil: false
        }
    }

    private var confirmTitle: String {
        switch model.presentation.confirm {
        case .deleteAccount: return "Delete your account?"
        case .deletePortraits(let ids):
            return ids.count >= 2 ? "Delete \(ids.count) portraits?" : "Delete this portrait?"
        case .deleteFolder: return "Delete this folder?"
        case .deleteBanner: return "Delete this banner?"
        case .coloriseAlreadyColour, nil: return ""
        }
    }

    private var confirmMessage: String {
        switch model.presentation.confirm {
        case .deleteAccount:
            return "This permanently deletes your account, cancels any subscription and removes your remaining credits. This can't be undone. Portraits stored on this Mac stay on this Mac."
        case .deletePortraits:
            return "This can't be undone."
        case .deleteFolder:
            return "Portraits in this folder are kept. This can't be undone."
        case .deleteBanner:
            return "This can't be undone."
        case .coloriseAlreadyColour, nil:
            return ""
        }
    }

    @ViewBuilder private var confirmButtons: some View {
        switch model.presentation.confirm {
        case .deleteAccount:
            Button("Delete account", role: .destructive) {
                Task { await entitlement.deleteAccount() }
                model.presentation.confirm = nil
            }
            Button("Cancel", role: .cancel) { model.presentation.confirm = nil }
        case .deletePortraits(let ids):
            Button("Delete", role: .destructive) {
                for id in ids {
                    if let p = portraits.first(where: { $0.persistentModelID == id }) {
                        modelContext.delete(p)
                    }
                }
                model.clearPortraitSelection()
                model.presentation.confirm = nil
            }
            Button("Cancel", role: .cancel) { model.presentation.confirm = nil }
        case .deleteFolder(let folderID):
            Button("Delete", role: .destructive) {
                if model.selectedFolderID == folderID { model.selectedFolderID = nil }
                if let folder = folders.first(where: { $0.persistentModelID == folderID }) {
                    modelContext.delete(folder)
                }
                model.presentation.confirm = nil
            }
            Button("Cancel", role: .cancel) { model.presentation.confirm = nil }
        case .deleteBanner(let bannerID):
            Button("Delete", role: .destructive) {
                if let banner = bannerDocs.first(where: { $0.persistentModelID == bannerID }) {
                    BannerDeletion.delete(banner, in: modelContext)
                }
                model.presentation.confirm = nil
            }
            Button("Cancel", role: .cancel) { model.presentation.confirm = nil }
        case .coloriseAlreadyColour, nil:
            EmptyView()
        }
    }
}

private struct BannerGalleryContextMenu: View {
    let banner: BannerDoc
    let model: ShellModel
    let onDismiss: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        DSContextMenuPanel {
            DSMenuRow("Open", icon: "arrow.up.forward") { onDismiss(); model.openBannerStudio(banner) }
            DSMenuRow("Rename", icon: "pencil") { onRename() }
            DSMenuRow("Duplicate", icon: "plus.square.on.square") { onDuplicate() }
            Divider().padding(.vertical, 2)
            DSMenuRow("Delete", icon: "trash", destructive: true) { onDelete() }
        }
    }
}
