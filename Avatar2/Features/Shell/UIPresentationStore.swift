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

/// Font-/weight-dropdowns in het Banner Text-paneel (geen native `Menu`).
enum BannerTextFieldMenu: Hashable, Sendable {
    case font(UUID)
    case weight(UUID)
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

/// Rechtermuis-menu zonder SwiftData-id (effect-key of banner-tekstlaag).
struct AnchoredMenuRequest: Equatable, Sendable {
    var id: String
    var anchor: CGRect
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
        case .createFolder: "createFolder"
        case .renameBanner(let id, _): "renameBanner-\(id)"
        case .createFolderForPortraits(let ids, _): "newFolder-\(ids.map(\.hashValue).description)"
        }
    }

    var title: String {
        switch self {
        case .renameFolder: "Rename folder"
        case .createFolder, .createFolderForPortraits: "Create folder"
        case .renameBanner: "Rename banner"
        }
    }

    var confirmLabel: String {
        switch self {
        case .createFolder, .createFolderForPortraits: "Create"
        case .renameFolder, .renameBanner: "Save"
        }
    }

    var fieldPlaceholder: String {
        switch self {
        case .renameFolder, .createFolder, .createFolderForPortraits: "Folder name"
        case .renameBanner: "Banner name"
        }
    }

    var initialDraft: String {
        switch self {
        case .renameFolder(_, let draft): draft
        case .createFolder(let draft): draft
        case .renameBanner(_, let draft): draft
        case .createFolderForPortraits(_, let draft): draft
        }
    }
}

enum PresentationConfirm: Equatable, Identifiable {
    case deleteAccount
    case deletePortraits(ids: [PersistentIdentifier])
    case deleteFolder(folderID: PersistentIdentifier)
    case deleteBanner(bannerID: PersistentIdentifier)
    /// Colorise op een foto die al in kleur lijkt — bevestig vóór de credit
    /// eraf gaat. De continue-actie leeft op `pendingColorise` zodat de
    /// dialog een tab-wissel overleeft (E53.7).
    case coloriseAlreadyColour

    var id: String {
        switch self {
        case .deleteAccount: "deleteAccount"
        case .deletePortraits(let ids): "deletePortraits-\(ids.map(\.hashValue).description)"
        case .deleteFolder(let id): "deleteFolder-\(id)"
        case .deleteBanner(let id): "deleteBanner-\(id)"
        case .coloriseAlreadyColour: "coloriseAlreadyColour"
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
    /// Boost-/Remove background-chip-dropdown in het Edit-paneel (E41.2).
    var editorChipMenu: ChipMenu?

    // MARK: Board session
    var boardCanvasMenu: CanvasToolbarMenu?
    var boardBatchMenu: BoardBatchMenu?
    var boardPortraitMenuID: PersistentIdentifier?
    var boardPortraitMenuAnchor: CGPoint = .zero

    // MARK: Banner studio session
    var bannerActiveTool: BannerTool?
    var bannerFloatingMenu: BannerFloatingMenu?
    /// Rechtermuis op een geselecteerde banner-tekstlaag (Delete).
    var bannerTextContextMenu: AnchoredMenuRequest?
    var bannerTextFieldMenu: BannerTextFieldMenu?

    // MARK: Settings
    var settingsThemeMenuOpen = false

    // MARK: Left nav
    var leftNavUserMenuOpen = false
    var leftNavFolderMenu: ContextMenuRequest?

    // MARK: Context menus (gallery/home/board)
    var portraitContextMenu: ContextMenuRequest?

    // MARK: Banner gallery
    var bannerGalleryMenu: ContextMenuRequest?

    // MARK: Portraits gallery
    /// Map-standaardachtergrond-dropdown in de gallery-kop (E53.7: was
    /// PortraitsGalleryView-@State en verdween bij elke view-recreatie).
    var folderBackgroundPickerOpen = false
    /// Gallery/home multi-select achtergrond-picker (Set background…).
    var selectionBackgroundPickerOpen = false
    var selectionBackgroundPickerAnchor: CGRect = .zero

    // MARK: Social preview
    var previewPicker: PreviewPicker?

    // MARK: Color pickers (caret-loos overlay i.p.v. systeem-popover)
    var colorPicker: PersistentColorPicker?

    // MARK: Effects — eigen effecten maken (E34)
    /// De "Create effect"-modal. Leeft hier (niet in `EffectsPanel`-@State) zodat
    /// 'ie een tab-/vensterwissel overleeft; de sheet hangt op ShellView.
    var createEffectSheetOpen = false
    /// Het resultaat van die modal. Het Effects-paneel consumeert 'm (en zet 'm
    /// daarna op nil) — de sheet leeft op de stabiele host, het EffectsModel in
    /// het paneel, dus de store is de brievenbus tussen die twee.
    var createdCustomEffect: CreateEffectResult?
    /// Rechtermuis op een eigen effect-kaart (Delete effect).
    var effectsContextMenu: AnchoredMenuRequest?

    // MARK: Alerts & confirms
    /// Een nieuw (ander) prompt seedt het concept; dezelfde alert opnieuw
    /// toewijzen laat de getypte tekst met rust.
    var alert: PresentationAlert? {
        didSet {
            if alert?.id != oldValue?.id { alertDraft = alert?.initialDraft ?? "" }
        }
    }
    /// Concepttekst van het open naam-prompt (rename/create folder, rename
    /// banner). Leeft hier — niet als @State op `FloatingOverlayHost` — zodat
    /// een vensterwissel (Cmd-Tab en terug) de getypte naam niet terugzet
    /// naar de originele.
    var alertDraft = ""
    var confirm: PresentationConfirm?
    /// Continue-actie voor `.coloriseAlreadyColour`. Wordt nil bij cancel/
    /// dismiss, zodat een hintergebleven closure niet later alsnog vuurt.
    var pendingColorise: (() -> Void)?

    // MARK: - Helpers

    func presentColoriseAlreadyColour(onConfirm: @escaping () -> Void) {
        pendingColorise = onConfirm
        confirm = .coloriseAlreadyColour
    }

    func dismissColoriseAlreadyColour() {
        pendingColorise = nil
        if confirm == .coloriseAlreadyColour { confirm = nil }
    }

    func confirmColoriseAlreadyColour() {
        let action = pendingColorise
        pendingColorise = nil
        if confirm == .coloriseAlreadyColour { confirm = nil }
        action?()
    }

    func dismissPortraitContextMenu() {
        portraitContextMenu = nil
    }

    func openSelectionBackgroundPicker(anchor: CGRect) {
        portraitContextMenu = nil
        selectionBackgroundPickerAnchor = anchor
        selectionBackgroundPickerOpen = true
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
        editorBackgroundColorPickerOpen = false
        editorChipMenu = nil
        boardCanvasMenu = nil
        boardBatchMenu = nil
        bannerFloatingMenu = nil
        bannerTextContextMenu = nil
        bannerTextFieldMenu = nil
        settingsThemeMenuOpen = false
        effectsContextMenu = nil
        leftNavUserMenuOpen = false
        leftNavFolderMenu = nil
        portraitContextMenu = nil
        bannerGalleryMenu = nil
        folderBackgroundPickerOpen = false
        selectionBackgroundPickerOpen = false
        colorPicker = nil
    }

    /// Einde van de editorsessie: library/home, of een ander beeld openen
    /// vanuit de gallery. Enhance (en chip-dropdowns) horen niet mee te
    /// reizen naar een nieuw portret. Tab-/vensterwissel raakt dit niet —
    /// `section` blijft dan `.editor`.
    func endEditorSession() {
        dismissAllEphemeral()
        editorActiveTool = nil
    }
}
