// Gedeelde presentatiestate (E53.7) — overleeft tab-/vensterwissel.
// Views lezen/schrijven via ShellModel.presentation; geen lokale @State
// voor open overlays of menu's.

import CoreGraphics
import Observation
import SwiftData
import SwiftUI

/// Board batch-toolbar dropdowns (los van editor `CanvasToolbarMenu`).
enum BoardBatchMenu: Hashable, Sendable {
    case background, adjust, align, organize
}

/// Banner floating-toolbar menu's.
enum BannerFloatingMenu: Hashable, Sendable {
    case textColor(layerID: UUID)
    case textFormat(layerID: UUID)
    case textSize(layerID: UUID)
    case imageInfo
}

/// Contextmenu-scope — bepaalt welk menu-template `FloatingOverlayHost` rendert.
enum ContextMenuScope: Hashable, Sendable {
    case home, portraitsGallery, portraitsList, portraitsCanvas, board, leftNavFolder
}

struct ContextMenuRequest: Equatable, Sendable {
    var portraitID: PersistentIdentifier?
    var folderID: PersistentIdentifier?
    var bannerID: PersistentIdentifier?
    var anchor: CGRect
    var scope: ContextMenuScope
}

enum PersistentColorPicker: Equatable, Sendable {
    case editorBackground
    case bannerBackground
    case bannerText(layerID: UUID)
    case bannerLogoBrand
}

// MARK: - Alerts & confirms (store-gedreven, stabiel op ShellView)

enum PresentationAlert: Equatable, Identifiable {
    case renameFolder(folderID: PersistentIdentifier, draft: String)
    case createFolder(draft: String)
    case renameBanner(bannerID: PersistentIdentifier, draft: String)
    case createFolderForPortraits(targetIDs: [PersistentIdentifier], draft: String)

    var id: String {
        switch self {
        case .renameFolder(let id, _): "renameFolder-\(id)"
        case .createFolder(let draft): "createFolder-\(draft)"
        case .renameBanner(let id, _): "renameBanner-\(id)"
        case .createFolderForPortraits(let ids, _): "newFolder-\(ids.map(\.hashValue).description)"
        }
    }
}

enum PresentationConfirm: Equatable, Identifiable {
    case deleteAccount
    case deletePortraits(ids: [PersistentIdentifier])
    case deleteFolder(folderID: PersistentIdentifier)
    case deleteBanner(bannerID: PersistentIdentifier)

    var id: String {
        switch self {
        case .deleteAccount: "deleteAccount"
        case .deletePortraits(let ids): "deletePortraits-\(ids.map(\.hashValue).description)"
        case .deleteFolder(let id): "deleteFolder-\(id)"
        case .deleteBanner(let id): "deleteBanner-\(id)"
        }
    }
}

@MainActor
@Observable
final class UIPresentationStore {
    // MARK: Editor session
    var editorCanvasMenu: CanvasToolbarMenu?
    var editorActiveTool: EditorTool?
    var editorBackgroundTypeMenuOpen = false
    var editorBackgroundColorPickerOpen = false

    // MARK: Board session
    var boardCanvasMenu: CanvasToolbarMenu?
    var boardBatchMenu: BoardBatchMenu?
    var boardPortraitMenuID: PersistentIdentifier?
    var boardPortraitMenuAnchor: CGPoint = .zero

    // MARK: Banner studio session
    var bannerActiveTool: BannerTool?
    var bannerFloatingMenu: BannerFloatingMenu?

    // MARK: Left nav
    var leftNavUserMenuOpen = false
    var leftNavFolderMenu: ContextMenuRequest?

    // MARK: Context menus (gallery/home/board)
    var portraitContextMenu: ContextMenuRequest?

    // MARK: Banner gallery
    var bannerGalleryMenu: ContextMenuRequest?

    // MARK: Social preview
    var previewPicker: PreviewPicker?

    // MARK: Color pickers (caret-loos overlay i.p.v. systeem-popover)
    var colorPicker: PersistentColorPicker?

    // MARK: Alerts & confirms
    var alert: PresentationAlert?
    var confirm: PresentationConfirm?

    // MARK: - Helpers

    func dismissPortraitContextMenu() {
        portraitContextMenu = nil
    }

    func openPortraitContextMenu(
        portraitID: PersistentIdentifier,
        anchor: CGRect,
        scope: ContextMenuScope
    ) {
        portraitContextMenu = ContextMenuRequest(
            portraitID: portraitID,
            folderID: nil,
            bannerID: nil,
            anchor: anchor,
            scope: scope
        )
    }

    func openFolderContextMenu(folderID: PersistentIdentifier, anchor: CGRect) {
        leftNavFolderMenu = ContextMenuRequest(
            portraitID: nil,
            folderID: folderID,
            bannerID: nil,
            anchor: anchor,
            scope: .leftNavFolder
        )
    }

    func dismissAllEphemeral() {
        editorCanvasMenu = nil
        editorBackgroundTypeMenuOpen = false
        boardCanvasMenu = nil
        boardBatchMenu = nil
        bannerFloatingMenu = nil
        leftNavUserMenuOpen = false
        leftNavFolderMenu = nil
        portraitContextMenu = nil
        bannerGalleryMenu = nil
        colorPicker = nil
    }
}
