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

    @State private var alertDraft = ""

    var body: some View {
        ZStack {
            portraitContextLayer
            leftNavFolderMenuLayer
            bannerGalleryMenuLayer
        }
        .alert(alertTitle, isPresented: Binding(
            get: { model.presentation.alert != nil },
            set: { if !$0 { model.presentation.alert = nil; alertDraft = "" } }
        )) {
            alertButtons
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(
                get: { model.presentation.confirm != nil },
                set: { if !$0 { model.presentation.confirm = nil } }
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
                    folders: folders,
                    selectedTargets: { portraits.filter { model.isPortraitSelected($0) } },
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
                        alertDraft = ""
                        model.presentation.alert = .createFolderForPortraits(
                            targetIDs: targets.map(\.persistentModelID),
                            draft: ""
                        )
                    }
                )
            }
        }
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
                DSContextMenuPanel(minWidth: 210) {
                    DSMenuRow("Select all in folder", icon: "checkmark.circle", disabled: items.isEmpty) {
                        model.presentation.leftNavFolderMenu = nil
                        model.showPortraits(folderID: folderID)
                        model.selectAllPortraits(items.map(\.persistentModelID))
                    }
                    DSMenuRow("Align set", icon: "align.horizontal.left", disabled: items.isEmpty) {
                        model.presentation.leftNavFolderMenu = nil
                        PortraitSetActions.align(items, undoManager: undoManager) { model.setBusyMessage = $0 }
                    }
                    DSMenuRow("Match lighting", icon: "sun.max", disabled: items.count < 2) {
                        model.presentation.leftNavFolderMenu = nil
                        guard let reference = FolderSetScope.matchLightingReference(items) else { return }
                        PortraitSetActions.matchLighting(
                            items, reference: reference, undoManager: undoManager
                        ) { model.setBusyMessage = $0 }
                    }
                    DSMenuRow("Export set", icon: "square.and.arrow.up.on.square", disabled: items.isEmpty) {
                        model.presentation.leftNavFolderMenu = nil
                        PortraitSetActions.export(items, isPro: model.isPro) { model.setBusyMessage = $0 }
                    }
                    Divider().padding(.vertical, 2)
                    DSMenuRow("Default background…", icon: "photo.on.rectangle") {
                        model.presentation.leftNavFolderMenu = nil
                        model.showFolderBackgroundPicker(folderID: folderID)
                    }
                    Divider().padding(.vertical, 2)
                    DSMenuRow("Rename", icon: "pencil") {
                        model.presentation.leftNavFolderMenu = nil
                        alertDraft = folder.name
                        model.presentation.alert = .renameFolder(folderID: folderID, draft: folder.name)
                    }
                    Divider().padding(.vertical, 2)
                    DSMenuRow("Delete", icon: "trash", destructive: true) {
                        model.presentation.leftNavFolderMenu = nil
                        model.presentation.confirm = .deleteFolder(folderID: folderID)
                    }
                }
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
                        alertDraft = banner.name
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

    // MARK: - Alerts

    private var alertTitle: String {
        switch model.presentation.alert {
        case .renameFolder: return "Rename folder"
        case .createFolder: return "Create folder"
        case .renameBanner: return "Rename banner"
        case .createFolderForPortraits: return "Create folder"
        case nil: return ""
        }
    }

    @ViewBuilder
    private var alertButtons: some View {
        if let alert = model.presentation.alert {
            switch alert {
            case .renameFolder(_, let draft):
                TextField("Folder name", text: Binding(
                    get: { alertDraft.isEmpty ? draft : alertDraft },
                    set: { alertDraft = $0 }
                ))
                Button("Save") { confirmRenameFolder(alert) }
                Button("Cancel", role: .cancel) { model.presentation.alert = nil }
            case .createFolder(let draft):
                TextField("Folder name", text: Binding(
                    get: { alertDraft.isEmpty ? draft : alertDraft },
                    set: { alertDraft = $0 }
                ))
                Button("Create") { confirmCreateFolder(alert) }
                Button("Cancel", role: .cancel) { model.presentation.alert = nil }
            case .renameBanner(_, let draft):
                TextField("Banner name", text: Binding(
                    get: { alertDraft.isEmpty ? draft : alertDraft },
                    set: { alertDraft = $0 }
                ))
                Button("Save") { confirmRenameBanner(alert) }
                Button("Cancel", role: .cancel) { model.presentation.alert = nil }
            case .createFolderForPortraits(_, let draft):
                TextField("Folder name", text: Binding(
                    get: { alertDraft.isEmpty ? draft : alertDraft },
                    set: { alertDraft = $0 }
                ))
                Button("Create") { confirmCreateFolderForPortraits(alert) }
                Button("Cancel", role: .cancel) { model.presentation.alert = nil }
            }
        }
    }

    private func confirmRenameFolder(_ alert: PresentationAlert) {
        defer { model.presentation.alert = nil }
        guard case .renameFolder(let folderID, _) = alert else { return }
        let name = alertDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              let folder = folders.first(where: { $0.persistentModelID == folderID }) else { return }
        folder.name = name
    }

    private func confirmCreateFolder(_ alert: PresentationAlert) {
        defer { model.presentation.alert = nil }
        guard case .createFolder = alert else { return }
        let name = alertDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        modelContext.insert(Folder2(name: name))
    }

    private func confirmRenameBanner(_ alert: PresentationAlert) {
        defer { model.presentation.alert = nil }
        guard case .renameBanner(let bannerID, _) = alert else { return }
        let name = alertDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              let banner = bannerDocs.first(where: { $0.persistentModelID == bannerID }) else { return }
        banner.name = name
    }

    private func confirmCreateFolderForPortraits(_ alert: PresentationAlert) {
        defer { model.presentation.alert = nil }
        guard case .createFolderForPortraits(let targetIDs, _) = alert else { return }
        let name = alertDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let folder = Folder2(name: name)
        modelContext.insert(folder)
        for id in targetIDs {
            if let p = portraits.first(where: { $0.persistentModelID == id }) {
                p.folder = folder
            }
        }
    }

    // MARK: - Confirms

    private var confirmTitle: String {
        switch model.presentation.confirm {
        case .deleteAccount: return "Delete your account?"
        case .deletePortraits(let ids):
            return ids.count >= 2 ? "Delete \(ids.count) portraits?" : "Delete this portrait?"
        case .deleteFolder: return "Delete this folder?"
        case .deleteBanner: return "Delete this banner?"
        case nil: return ""
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
        case nil:
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
        case nil:
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
