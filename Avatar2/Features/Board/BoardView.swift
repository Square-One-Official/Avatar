// Board-view (E27.4) — de hele portret-set als een scene-graph van kaart-nodes
// op één oneindig board, met de canvas-camera uit E27.1 (scale + offset)
// eroverheen: pan (scroll/spatie-drag), zoom (pinch/⌘-scroll/⌘±/⌘0=fit) over de
// héle set. Nodes zijn sleepbaar (positie persisteert op Portrait2.boardX/Y,
// undo'baar); klik een portret → openen in de editor.
//
// Fase 2 (steps 1-3 van het E27.4-plan): persistente posities + fit-to-content +
// drag. Inline-editen-op-de-node (zonder de board te verlaten) is fase 2b.
// De productie-editor-flow blijft ongemoeid; de board is een aparte modus.

import AppKit
import AvatarKit
import AvatarUI
import SwiftData
import SwiftUI

struct BoardView: View {
    /// Folder-scope (Portraits-canvas-lens): nil = alle beelden, anders alleen de
    /// portretten van die map. Default nil → ongewijzigd gedrag.
    var folderID: PersistentIdentifier? = nil
    /// Dezelfde bron als de sidebar (E05.4): alle portretten, jongste eerst.
    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var allPortraits: [Portrait2]
    /// Folder-gescope set die HEEL BoardView aanstuurt (layout/selectie/
    /// visibleNodes/boardSize). Eén plek scopen → alle call-sites volgen vanzelf.
    private var portraits: [Portrait2] {
        guard let folderID else { return allPortraits }
        return allPortraits.filter { $0.folder?.persistentModelID == folderID }
    }
    /// E30.1: dezelfde edit-pipeline als de editor — bij één-selectie zetten we
    /// `model.selectedPortrait` op de node en hergebruiken we model.applyEffectResult
    /// (cloud-re-isolatie!) / commitAdjust i.p.v. die logica te dupliceren.
    let model: ShellModel
    let entitlement: EntitlementModel
    /// Dubbelklik op een node → openen (selecteren) in de editor.
    let onOpen: (Portrait2) -> Void

    @Environment(\.undoManager) private var undoManager
    /// UXS-15: transitions op de board honoreren "Verminder beweging".
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Delete-actie van het rechtermuis-menu (zelfde modelContext-pad als de sidebar).
    @Environment(\.modelContext) private var modelContext

    // E30.1 / E31.7: actief bottom-tool bij ÉÉN geselecteerde node (in-place
    // editen op de board). Dezelfde `EditorTool` als de single-editor zodat de
    // board exact dezelfde capsule-items/labels/iconen toont.
    @State private var editTool: EditorTool?
    /// Perf (2026-09-03): decode-memo voor de single-edit-panelen. `NSImage(data:)`
    /// in de body gaf bij élke pass een nieuwe bron-identiteit, waardoor de
    /// preview-task van `EditColorPanel` (`.task(id:)`) op elke render herstartte.
    @State private var singleEditImages = SingleEditImageMemo()
    /// Klik buiten batch-bar + open dropdown (waar dan ook) sluit de dropdown.
    @State private var batchMenuClickScope = DSOutsideClickScope()
    /// Idem voor het rechtermuis-menu op een node.
    @State private var nodeMenuClickScope = DSOutsideClickScope()

    /// De enige geselecteerde node (nil bij 0 of ≥2) — de in-place-edit-target.
    private var boardToolbarItems: [DSToolbarItem<EditorTool>] {
        EditorView.toolbarItems.filter { $0.id.isEnabled(remote: entitlement.featureFlags) }
    }

    private var selectedNode: Portrait2? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return portraits.first { $0.persistentModelID == id }
    }

    private var boardCanvasMenuBinding: Binding<CanvasToolbarMenu?> {
        Binding(
            get: { model.presentation.boardCanvasMenu },
            set: { model.presentation.boardCanvasMenu = $0 }
        )
    }

    /// E27.6 (Tier 3): off-main thumbnail-store — decodeert elke cutout één keer
    /// per (id, revision, maat) op een achtergrond-Task (geen main-thread-hitch),
    /// (id, revision)-gekeyd zodat edits vanzelf verversen, met FIFO-eviction tegen
    /// onbegrensd geheugen bij honderden nodes. Referentietype zodat het over
    /// body-evaluaties heen leeft.
    @State private var thumbs = ThumbnailStore()

    // Camera met een lagere min-zoom dan de editor, zodat een grote set in beeld past.
    @State private var camera = CanvasCamera(minScale: 0.1)
    @State private var viewport: CGSize = .zero
    /// De laatst auto-gefitte camera. Zolang de camera hieraan gelijk is (de
    /// gebruiker heeft 'm niet aangeraakt) blijft de board mee-fitten op
    /// viewport-/set-wijzigingen; zodra de gebruiker pant/zoomt (camera ≠ deze)
    /// stopt het auto-fitten.
    @State private var lastFit: CanvasCamera?

    // Drag-state (board-space): per-portrait startposities zodat een multi-select
    // als groep versleept kan worden met één gezamenlijke translatie.
    @State private var dragStartPositions: [PersistentIdentifier: CGPoint] = [:]

    // E29.1: multi-select op de board.
    @State private var selection: Set<PersistentIdentifier> = []
    /// E29.4: range-anker voor shift-klik — de laatst kaal/cmd-geselecteerde
    /// node; shift-klik selecteert alles tussen dit anker en de aangeklikte node.
    @State private var selectionAnchor: PersistentIdentifier?
    /// Marquee-rechthoek (board-space) tijdens een sleep op de lege board.
    @State private var marquee: CGRect?
    /// Basis-selectie vastgelegd bij de start van een marquee-sleep, zodat
    /// cmd/shift (additief) tegen een vaste set rekent i.p.v. de live-groeiende.
    @State private var marqueeBase: Set<PersistentIdentifier> = []

    // Rechtermuis-context-menu op een node — pariteit met het sidebar-menu
    // (E24.22: Rename · Export… · Delete). Geen native `.contextMenu`; we tekenen
    // ons eigen DS-menu (zie de overlay onder in `body`), gepositioneerd onder de
    // aangeklikte node. Bij een multi-selectie (≥2) werken Rename/Export/Delete op
    // de hele selectie — vandaar lijsten i.p.v. één target.
    /// Bulk-export-status (board heeft geen shell-toast) → getoond in de HUD.
    @State private var exportStatus: String?

    private var selectedPortraits: [Portrait2] {
        portraits.filter { selection.contains($0.persistentModelID) }
    }

    private var boardMenuTarget: Portrait2? {
        guard let id = model.presentation.boardPortraitMenuID else { return nil }
        return portraits.first { $0.persistentModelID == id }
    }

    private func dismissBoardMenu() {
        model.presentation.boardPortraitMenuID = nil
    }

    // Node-/cel-maten (board-space).
    private let cardSide: CGFloat = 200
    private let labelHeight: CGFloat = 38
    private let labelGap: CGFloat = 8
    private let gap: CGFloat = 48
    private let margin: CGFloat = 140

    private var cellHeight: CGFloat { cardSide + labelGap + labelHeight }
    private var columns: Int { max(1, Int(ceil(Double(portraits.count).squareRoot()))) }
    private var rows: Int { max(1, Int(ceil(Double(portraits.count) / Double(columns)))) }

    /// Vaste board-canvas-maat uit de grid-extent + marge (stabiel: hangt niet
    /// van live drag-posities af, dus nodes springen niet bij het slepen).
    private var boardSize: CGSize {
        CGSize(
            width: CGFloat(columns) * cardSide + CGFloat(columns - 1) * gap + 2 * margin,
            height: CGFloat(rows) * cellHeight + CGFloat(rows - 1) * gap + 2 * margin
        )
    }

    var body: some View {
        // GEEN top-level GeometryReader: die is gulzig en perst de left-nav smaller
        // in board-view (de scroll-lenzen niet). De inhoud vult 'polite' via
        // .frame(maxWidth/maxHeight: .infinity); de viewport-maat meten we in een
        // .background(GeometryReader), wat de omliggende layout niet beïnvloedt.
            ZStack {
                DSColor.Background.app

                // Viewport-vullende laag voor marquee + deselect-all — ONDER boardCanvas
                // zodat node-gestures (bovenliggende laag) prioriteit houden. Altijd
                // volledig zichtbaar, ongeacht camera.scale, zodat de gebruiker ook van
                // buiten het visueel verkleinde canvas kan beginnen te slepen.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selection.removeAll() }
                    .gesture(viewportMarqueeGesture)

                if portraits.isEmpty {
                    Text("No portraits yet")
                        .dsTextStyle(.bodyMedium)
                        .foregroundStyle(DSColor.Foreground.muted)
                } else {
                    boardCanvas
                        .frame(width: boardSize.width, height: boardSize.height)
                        .scaleEffect(camera.scale, anchor: .center)
                        .offset(camera.offset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        // Flatten camera-geschaalde Image-nodes tot één laag zodat
                        // toolbar/Background-dropdowns er betrouwbaar bóven liggen.
                        .compositingGroup()
                        .background {
                            CanvasInteractionCatcher(
                                camera: $camera,
                                chromeHovered: model.presentation.boardBatchMenu != nil
                                    || model.presentation.boardCanvasMenu != nil
                            )
                            boardShortcutButtons
                        }
                }

                hud
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "boardRoot")
            // E29.2: batch-toolbar bovenaan zodra er ≥1 geselecteerd is. Als
            // top-overlay (deterministisch) + padding om onder de app-topbar te
            // blijven.
            .overlay(alignment: .top) {
                // E30.1: ≥2 geselecteerd → batch-toolbar (Match lighting hoort
                // bij meerdere). Precies 1 → de NORMALE editor-toolbar (Frame/
                // Background/Adjust/Flip) op de node, niet de batch-framing.
                Group {
                    if selection.count >= 2 {
                        boardBatchBar
                            .transition(.dsScaleFade(anchor: .top, reduceMotion: reduceMotion))
                    } else if let node = selectedNode {
                        singleEditTopBar(node)
                            // Horizontaal gecentreerd boven de geselecteerde node.
                            // Inverse van visibleBoardRect-transform: het overlay-nulpunt
                            // ligt op vpMidden, dus offset = scale·(boardX−boardMidden)+cameraOffset.
                            .offset(x: camera.scale * (node.boardX - boardSize.width / 2)
                                + camera.offset.width)
                            .transition(.dsScaleFade(anchor: .top, reduceMotion: reduceMotion))
                    }
                }
                .padding(.top, 70)
                // Background/Frame-menu's moeten boven de portret-rij blijven.
                .zIndex(1000)
                // UXS-15 (UX16): batch↔single wisselde zonder enige transitie —
                // een state-wissel die je tientallen keren per dag ziet hoort
                // subtiel te bewegen. Respecteert reduce-motion via dsMotion.
                .dsMotion(DSMotion.fast, value: selection.count >= 2)
            }
            // E30.1: bij één-selectie de editor-bottom-tools (Effects/Face/
            // Clothing/Hair) op de node — zodat in-place editen op de board kan.
            .overlay(alignment: .bottom) {
                if let node = selectedNode {
                    singleEditBottomBar(node)
                        .padding(.bottom, 64)
                }
            }
            // Rechtermuis-menu — gepositioneerd onder de aangeklikte node; een
            // transparante scrim eronder sluit bij een klik buiten het menu.
            .overlay {
                if let target = boardMenuTarget {
                    contextMenuOverlay(target)
                }
            }
            // Viewport-maat meten zónder gulzige top-level GeometryReader: een
            // .background(GeometryReader) matcht de inhoudsmaat en raakt de layout niet.
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { viewport = geo.size; assignInitialLayout(); fitIfNeeded(); debugSeedSelection() }
                        .onChange(of: geo.size) { _, s in viewport = s; fitIfNeeded() }
                }
            )
            // @Query laadt ná de eerste render → layout + fit zodra de set binnen
            // is; `didInitialFit` latcht pas bij een niet-lege set.
            .onChange(of: portraits.count) { _, _ in assignInitialLayout(); fitIfNeeded() }
            // E30.1: één-selectie → richt de gedeelde edit-pipeline op die node;
            // bij 0 of ≥2 sluit het bottom-tool-paneel.
            .onChange(of: selection) { _, sel in
                // Sluit altijd alle dropdowns bij selectie-wissel — anders
                // heropen de batch-bar met een nog-open dropdown.
                model.presentation.boardBatchMenu = nil
                model.presentation.boardCanvasMenu = nil
                if sel.count == 1, let id = sel.first,
                   let node = portraits.first(where: { $0.persistentModelID == id }) {
                    model.select(node)
                } else {
                    editTool = nil
                }
            }
            // E27.10 (audit C2): één gedeeld zoom-mechanisme voor editor én
            // board — de board publiceert dezelfde focused-scene-value, dus de
            // View-menu-items (⌘+/⌘−/⌘0) werken hier nu ook; de eigen verborgen
            // +/=/−/0-knoppen zijn uit `boardShortcutButtons` vervallen.
            .focusedSceneValue(\.canvasZoom, CanvasZoomActions(
                zoomIn: { zoom(1.25) },
                zoomOut: { zoom(0.8) },
                zoomToFit: { fit() }
            ))
            // ⌘= (shift-loze ⌘+) — zelfde verborgen brug als de editor.
            .background { CanvasZoomEqualsShortcut(zoomIn: { zoom(1.25) }) }
    }

    // MARK: - Board-canvas (absolute node-posities)

    private var boardCanvas: some View {
        ZStack(alignment: .topLeading) {
            // Onzichtbaar vlak dat de board-maat bepaalt (de nodes positioneren
            // hierop absoluut). Gestures zijn verplaatst naar de viewport-laag in
            // `body` zodat ze werken ongeacht het camera-schaal-niveau.
            Color.clear
                .allowsHitTesting(false)

            // E27.5: virtualisatie — alleen nodes die in (of net buiten) de
            // zichtbare viewport vallen, renderen. Scheelt views + werk bij pan/
            // zoom op een grote set.
            ForEach(visibleNodes(), id: \.portrait.persistentModelID) { item in
                // E-fix (schone build): de node + al z'n modifiers staan in een aparte
                // methode i.p.v. inline. Eén grote ForEach-closure (14-arg BoardNodeView
                // + `.equatable()` + 6 modifiers + gestures) tipte de Swift type-checker
                // over z'n complexiteitslimiet bij een schone build (incrementeel
                // hergebruikte de oude .o, dus onzichtbaar) → de misleidende
                // "ForEach … Binding<C>"-cascade. Extractie houdt de inferentie klein.
                boardNode(item)
            }

            // E29.1: marquee-rechthoek (board-space; lijn ÷camera = constant dun).
            if let marquee {
                Rectangle()
                    .fill(DSColor.Action.primary.opacity(0.12))
                    .overlay(Rectangle().strokeBorder(DSColor.Action.primary, lineWidth: 1 / camera.scale))
                    .frame(width: marquee.width, height: marquee.height)
                    .position(x: marquee.midX, y: marquee.midY)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Viewport-coördinaat → board-coördinaat (inverse van `screenPoint`).
    private func toBoardSpace(_ p: CGPoint) -> CGPoint {
        let vpC  = CGPoint(x: viewport.width  / 2, y: viewport.height  / 2)
        let brdC = CGPoint(x: boardSize.width / 2, y: boardSize.height / 2)
        return CGPoint(
            x: brdC.x + (p.x - vpC.x - camera.offset.width)  / camera.scale,
            y: brdC.y + (p.y - vpC.y - camera.offset.height) / camera.scale
        )
    }

    /// E29.1: marquee — sleep op de viewport spant een selectie-rechthoek;
    /// nodes waarvan het midden erin valt worden geselecteerd (cmd/shift =
    /// toevoegen aan de bestaande selectie). De selectie loopt live mee tijdens
    /// de sleep. Zit op de viewport-laag (niet binnen boardCanvas) zodat de
    /// gebruiker ook buiten het visueel verkleinde canvas kan beginnen te slepen.
    /// Viewport-coördinaten worden on-the-fly omgezet naar board-space via
    /// `toBoardSpace(_:)`.
    private var viewportMarqueeGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("boardRoot"))
            .onChanged { value in
                if marquee == nil {
                    let additive = NSEvent.modifierFlags.contains(.command)
                        || NSEvent.modifierFlags.contains(.shift)
                    marqueeBase = additive ? selection : []
                }
                let start = toBoardSpace(value.startLocation)
                let end   = toBoardSpace(value.location)
                let rect  = CGRect(
                    x: min(start.x, end.x), y: min(start.y, end.y),
                    width: abs(end.x - start.x), height: abs(end.y - start.y)
                )
                marquee = rect
                let hits = Set(
                    portraits.enumerated()
                        .filter { rect.contains(center(of: $1, index: $0)) }
                        .map { $1.persistentModelID }
                )
                selection = marqueeBase.union(hits)
            }
            .onEnded { _ in
                marquee = nil
            }
    }

    /// E27.5: de nodes waarvan het midden binnen de (met een cel-marge verruimde)
    /// zichtbare board-rect valt. Vóór de eerste layout (viewport 0) → alles.
    /// E27.6 (Tier 2): één `compactMap` die ALLEEN de zichtbare tuples alloceert —
    /// geen tussen-array van álle portretten meer per camera-frame. `center(of:)` is
    /// goedkoop (leest boardX/boardY of de auto-grid-plek) en blijft live, dus
    /// node-drag + `BoardMoveUndo` verschuiven direct, zonder een aparte cache te
    /// syncen. (Bij echte duizenden: een grid-bucket-index i.p.v. de O(n)-scan — pas
    /// als profiling het vraagt.)
    /// De node + al z'n modifiers (zie de extractie-reden bij de ForEach). Los
    /// gehouden zodat de type-checker elke node-expressie klein genoeg houdt.
    /// E27.6: de visuals zitten in de `Equatable` BoardNodeView (pan/zoom-only =
    /// `==` blijft → body geskipt); gestures/hover hangen erbuiten.
    private func boardNode(_ item: (portrait: Portrait2, center: CGPoint)) -> some View {
        let p = item.portrait
        // De achtergrondLAAG ÍS de originele foto (Original-modus, of Portrait-blur
        // zonder eigen achtergrond) → spiegelt EditorView.backgroundIsAlignedOriginal.
        let bgIsAlignedOriginal = p.backgroundImageData == nil
            && p.backgroundColorHex == nil
            && (p.useOriginalBackground || p.portraitBlur)
        return BoardNodeView(
            thumbnail: thumbs.thumbnail(for: p, maxDimension: cardSide * 2),
            backgroundOriginalImage: bgIsAlignedOriginal
                ? thumbs.originalBackdrop(for: p, maxDimension: cardSide * 2)
                : nil,
            isSelected: selection.contains(p.persistentModelID),
            frameShape: p.frameShape,
            name: p.name,
            role: p.role,
            backgroundColorHex: p.backgroundColorHex,
            backgroundImageData: p.backgroundImageData,
            portraitBlur: p.portraitBlur,
            contentVersion: p.revision,
            cardSide: cardSide,
            labelGap: labelGap,
            labelHeight: labelHeight,
            cellHeight: cellHeight
        )
        .equatable()
        .contentShape(Rectangle())
        .dsHoverHighlight(cornerRadius: DSRadius.xl4)
        // Dubbelklik = openen in de editor; enkelklik = selecteren. Sleep = node
        // verplaatsen (E27.4).
        // E29.4 (audit C5): expliciete modifier-gestures i.p.v. de globale
        // `NSEvent.modifierFlags` onder een tap (fragiel — cmd/shift-klik verving
        // live de selectie i.p.v. te toggelen). Cmd = toggle, shift = range
        // uitbreiden (macOS/Finder-conventie), kale klik = vervang. Volgorde is
        // prioriteit: eerder-attached gestures winnen, dus de modifier-varianten
        // vóór de kale tap.
        .onTapGesture(count: 2) { onOpen(p) }
        .gesture(TapGesture().modifiers(.command).onEnded { toggleNodeSelection(p) })
        .gesture(TapGesture().modifiers(.shift).onEnded { extendSelectionRange(to: p) })
        .gesture(TapGesture().onEnded { selectOnly(p) })
        // Rechtermuis → DS-menu; selecteert de node eerst als 'ie nog niet in de
        // selectie zit (Finder), zodat "Export N…" alleen bij een echte multi-
        // selectie verschijnt; binnen een bestaande ≥2-selectie blijft die staan.
        .onRightClick {
            if !selection.contains(p.persistentModelID) { selection = [p.persistentModelID] }
            model.presentation.boardPortraitMenuID = p.persistentModelID
            model.presentation.boardPortraitMenuAnchor = menuAnchor(for: p)
        }
        .gesture(dragGesture(for: p))
        .position(x: item.center.x, y: item.center.y)
    }

    private func visibleNodes() -> [(portrait: Portrait2, center: CGPoint)] {
        guard viewport.width > 0, viewport.height > 0, camera.scale > 0 else {
            return portraits.enumerated().map { (portrait: $1, center: center(of: $1, index: $0)) }
        }
        let rect = visibleBoardRect().insetBy(dx: -(cardSide + gap), dy: -(cellHeight + gap))
        return portraits.enumerated().compactMap { index, p in
            let c = center(of: p, index: index)
            return rect.contains(c) ? (portrait: p, center: c) : nil
        }
    }

    /// De zichtbare board-rect (board-space) gegeven de camera + viewport.
    /// scherm = vpMidden + scale·(p − boardMidden) + offset  ⇒  p = boardMidden +
    /// (scherm − vpMidden − offset)/scale.
    private func visibleBoardRect() -> CGRect {
        let vpC = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let boardC = CGPoint(x: boardSize.width / 2, y: boardSize.height / 2)
        func boardPoint(_ s: CGPoint) -> CGPoint {
            CGPoint(
                x: boardC.x + (s.x - vpC.x - camera.offset.width) / camera.scale,
                y: boardC.y + (s.y - vpC.y - camera.offset.height) / camera.scale
            )
        }
        let tl = boardPoint(.zero)
        let br = boardPoint(CGPoint(x: viewport.width, y: viewport.height))
        return CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
    }

    // MARK: - E29.4 selectie-semantiek (audit C5)

    /// Kale klik — vervang de selectie door alléén deze node; de node wordt het
    /// range-anker voor een latere shift-klik.
    private func selectOnly(_ portrait: Portrait2) {
        let id = portrait.persistentModelID
        selection = [id]
        selectionAnchor = id
    }

    /// Cmd-klik — toggle de node in/uit de selectie (macOS-conventie). Een
    /// toegevoegde node wordt het nieuwe range-anker; valt het anker zelf uit de
    /// selectie, dan schuift het anker naar een resterende node.
    private func toggleNodeSelection(_ portrait: Portrait2) {
        let result = Self.toggledSelection(
            current: selection, anchor: selectionAnchor,
            toggling: portrait.persistentModelID
        )
        selection = result.selection
        selectionAnchor = result.anchor
    }

    /// Pure toggle-semantiek (E47.3-seam; unit-getest in `BoardSelectionTests`,
    /// zelfde patroon als `rangeExtendedSelection`): cmd-klik voegt een node toe
    /// (die wordt het nieuwe anker) of haalt 'm eruit; verdwijnt het anker zelf
    /// uit de selectie, dan schuift het anker naar een resterende node (of nil
    /// bij een lege selectie). Gedrag identiek aan de oude inline-variant.
    static func toggledSelection<ID: Hashable>(
        current: Set<ID>, anchor: ID?, toggling id: ID
    ) -> (selection: Set<ID>, anchor: ID?) {
        var selection = current
        var anchor = anchor
        if selection.contains(id) {
            selection.remove(id)
            if anchor == id { anchor = selection.first }
        } else {
            selection.insert(id)
            anchor = id
        }
        return (selection, anchor)
    }

    /// Shift-klik — breid de selectie uit met de RANGE anker→node in
    /// board-volgorde (Finder-conventie: shift = range, cmd = toggle; shift is
    /// dus géén toggle-alias van cmd meer). Zonder (geldig) anker: additief.
    private func extendSelectionRange(to portrait: Portrait2) {
        let id = portrait.persistentModelID
        selection = Self.rangeExtendedSelection(
            current: selection,
            anchor: selectionAnchor,
            target: id,
            order: portraits.map(\.persistentModelID)
        )
        if selectionAnchor == nil { selectionAnchor = id }
    }

    /// Pure range-uitbreiding (unit-getest in `BoardSelectionTests`): union van
    /// de bestaande selectie met alle nodes tussen anker en doel (inclusief,
    /// beide richtingen) in de gegeven volgorde. Geen/onbekend anker → alleen
    /// het doel erbij (additief).
    static func rangeExtendedSelection<ID: Hashable>(
        current: Set<ID>, anchor: ID?, target: ID, order: [ID]
    ) -> Set<ID> {
        guard let anchor,
              let anchorIndex = order.firstIndex(of: anchor),
              let targetIndex = order.firstIndex(of: target) else {
            return current.union([target])
        }
        return current.union(order[min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)])
    }

    // MARK: - Rechtermuis-context-menu (pariteit met de sidebar, E24.22)

    /// Het zwevende DS-menu + de dismiss-scrim, gepositioneerd onder de node.
    @ViewBuilder
    private func contextMenuOverlay(_ target: Portrait2) -> some View {
        let anchor = menuAnchor(for: target)
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismissBoardMenu() }
            nodeContextMenu(for: target)
                .dsDismissOnOutsideClick(nodeMenuClickScope, isActive: true) { dismissBoardMenu() }
                .fixedSize()
                .offset(x: anchor.x, y: anchor.y)
        }
    }

    /// Rij-opties zoals het sidebar-menu. Bij een multi-selectie (≥2) werken alle
    /// acties op de hele selectie (count-gelabeld); bij één node op die node. De
    /// rechtermuis-handler zorgt dat de aangeklikte node altijd in de selectie zit,
    /// dus `selection.count` is hier de juiste maat.
    @ViewBuilder
    private func nodeContextMenu(for portrait: Portrait2) -> some View {
        let bulk = selection.count >= 2
        let n = selection.count
        DSContextMenuPanel {
            if bulk {
                DSMenuRow("Rename \(n) portraits", icon: "pencil") {
                    dismissBoardMenu()
                    model.renamePortraitIDs = selectedPortraits.map(\.persistentModelID)
                }
                DSMenuRow("Export \(n) portraits", icon: "square.and.arrow.up.on.square") {
                    dismissBoardMenu(); bulkExport()
                }
                // E57.6: dezelfde Edit-tak als het tegelmenu (Boost / Fill in
                // body / Apply effect), op de hele selectie.
                PortraitEditSubmenu(
                    targets: selectedPortraits, model: model, entitlement: entitlement,
                    undoManager: undoManager, onDismiss: dismissBoardMenu
                )
                Divider().padding(.vertical, 2)
                DSMenuRow("Delete \(n) portraits", icon: "trash", destructive: true) {
                    dismissBoardMenu()
                    model.presentation.confirm = .deletePortraits(
                        ids: selectedPortraits.map(\.persistentModelID)
                    )
                }
            } else {
                DSMenuRow("Rename", icon: "pencil") {
                    dismissBoardMenu()
                    model.renamePortraitIDs = [portrait.persistentModelID]
                }
                DSMenuRow("Export…", icon: "square.and.arrow.up") {
                    dismissBoardMenu(); model.select(portrait); model.exportCurrentPortrait()
                }
                PortraitEditSubmenu(
                    targets: [portrait], model: model, entitlement: entitlement,
                    undoManager: undoManager, onDismiss: dismissBoardMenu
                )
                Divider().padding(.vertical, 2)
                DSMenuRow("Delete", icon: "trash", destructive: true) {
                    dismissBoardMenu()
                    model.presentation.confirm = .deletePortraits(ids: [portrait.persistentModelID])
                }
            }
        }
    }

    /// Top-leading van het menu (viewport-space), net onder de node-kaart en
    /// links uitgelijnd — geklemd binnen de viewport zodat het altijd zichtbaar
    /// blijft. Schatting van de menuhoogte (200) volstaat voor het klemmen.
    private func menuAnchor(for portrait: Portrait2) -> CGPoint {
        let c = nodeCenter(portrait)
        // De kaart vult de bovenste `cardSide` van de cel; pak de onder-leading hoek.
        let leadingBottom = CGPoint(x: c.x - cardSide / 2, y: c.y - cellHeight / 2 + cardSide)
        let s = screenPoint(leadingBottom)
        // Klem op de breedste realistische variant (content-fit bulk ≈ 210) zodat
        // het menu altijd in beeld blijft.
        let menuW: CGFloat = 210
        let menuH: CGFloat = 200
        let pad = DSSpacing.gap2
        let x = min(max(s.x, pad), max(pad, viewport.width - menuW - pad))
        let y = min(max(s.y + pad, pad), max(pad, viewport.height - menuH - pad))
        return CGPoint(x: x, y: y)
    }

    /// Board-punt → viewport-punt (inverse van de camera-transform; zie
    /// `visibleBoardRect`): scherm = vpMidden + scale·(p − boardMidden) + offset.
    private func screenPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: viewport.width / 2 + camera.scale * (p.x - boardSize.width / 2) + camera.offset.width,
            y: viewport.height / 2 + camera.scale * (p.y - boardSize.height / 2) + camera.offset.height
        )
    }

    /// Board-midden van een node, los van de virtualisatie-index (placed → de
    /// persistente plek; anders de auto-grid-plek op z'n lijst-index).
    private func nodeCenter(_ portrait: Portrait2) -> CGPoint {
        if portrait.boardPlaced { return CGPoint(x: portrait.boardX, y: portrait.boardY) }
        let i = portraits.firstIndex { $0.persistentModelID == portrait.persistentModelID } ?? 0
        return autoCenter(order: i)
    }

    /// Bulk-export van de selectie (≥2) naar een gekozen map — spiegelt de
    /// sidebar (E19.4): watermerk voor free, status in de HUD.
    private func bulkExport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder to export the selected portraits"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let targets = selectedPortraits
        guard !targets.isEmpty else { return }
        let watermark = !entitlement.isProActive
        exportStatus = "Exporting \(targets.count) portraits…"
        Task { @MainActor in
            for (i, p) in targets.enumerated() {
                guard let data = PortraitExporter.makePNG(for: p, watermark: watermark, shape: p.frameShape) else { continue }
                let base = p.name.trimmingCharacters(in: .whitespaces)
                let name = (base.isEmpty ? "portrait-\(i + 1)" : base.replacingOccurrences(of: "/", with: "-")) + ".png"
                try? data.write(to: dir.appendingPathComponent(name))
            }
            exportStatus = nil
        }
    }

    // MARK: - Layout / posities

    /// Node-midden in board-space: persistente positie, of de auto-grid-plek.
    private func center(of portrait: Portrait2, index: Int) -> CGPoint {
        if portrait.boardPlaced {
            return CGPoint(x: portrait.boardX, y: portrait.boardY)
        }
        return autoCenter(order: index)
    }

    private func autoCenter(order i: Int) -> CGPoint {
        let col = i % columns
        let row = i / columns
        return CGPoint(
            x: margin + CGFloat(col) * (cardSide + gap) + cardSide / 2,
            y: margin + CGFloat(row) * (cellHeight + gap) + cellHeight / 2
        )
    }

    /// Nog niet-geplaatste nodes een board-positie geven (persistent, zodat ze
    /// daarna sleepbaar/stabiel zijn). Wijzigt geen `updatedAt`.
    /// - Eerste keer (niets geplaatst): auto-grid.
    /// - Nieuwe import terwijl er al nodes staan: NIET autoCenter(index) — dat
    ///   botste met de al-vastgepinde node op die grid-cel (en de nieuwste rendert
    ///   onderaan de ZStack → onzichtbaar erachter). Plaats 'm in een verse rij
    ///   ONDER de bestaande content, selecteer 'm en centreer de camera erop zodat
    ///   de net-geïmporteerde foto meteen in beeld + gemarkeerd staat.
    private func assignInitialLayout() {
        let unplaced = portraits.filter { !$0.boardPlaced }
        guard !unplaced.isEmpty else { return }
        let placed = portraits.filter { $0.boardPlaced }

        if placed.isEmpty {
            for (index, portrait) in portraits.enumerated() where !portrait.boardPlaced {
                let c = autoCenter(order: index)
                portrait.boardX = c.x; portrait.boardY = c.y
                portrait.boardOrder = index; portrait.boardPlaced = true
            }
            return
        }

        // Verse rij onder de laagste bestaande node (gegarandeerd vrij).
        let rowY = (placed.map(\.boardY).max() ?? margin) + cellHeight + gap
        var x = margin + cardSide / 2
        var order = (placed.map(\.boardOrder).max() ?? 0) + 1
        var newest: Portrait2?
        for portrait in unplaced {
            portrait.boardX = x; portrait.boardY = rowY
            portrait.boardOrder = order; portrait.boardPlaced = true
            x += cardSide + gap; order += 1
            newest = portrait
        }
        if let newest {
            selection = [newest.persistentModelID]
            centerCamera(on: CGPoint(x: newest.boardX, y: newest.boardY))
        }
    }

    /// Centreer de camera op een board-punt (zodat het in de viewport valt).
    /// scherm = vpMidden + scale·(p − boardMidden) + offset = vpMidden ⇒
    /// offset = −scale·(p − boardMidden).
    private func centerCamera(on p: CGPoint) {
        let boardC = CGPoint(x: boardSize.width / 2, y: boardSize.height / 2)
        camera.offset = CGSize(
            width: -camera.scale * (p.x - boardC.x),
            height: -camera.scale * (p.y - boardC.y)
        )
        lastFit = camera  // gericht gecentreerd → auto-fit niet laten overschrijven
    }

    /// E29.1 smoke-haak: `--board-select <n>` selecteert de eerste n portretten.
    /// `--show-board-menu` forceert daarnaast het rechtermuis-menu (positie/render).
    private func debugSeedSelection() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--board-select"), args.indices.contains(i + 1),
           let n = Int(args[i + 1]) {
            selection = Set(portraits.prefix(n).map { $0.persistentModelID })
            // E29.2 smoke: pas een batch-achtergrond toe op de selectie ("none" = wissen).
            if let j = args.firstIndex(of: "--board-batch-bg"), args.indices.contains(j + 1) {
                let v = args[j + 1]
                applyBackgroundToAll(v == "none" ? .transparent : .color(v))
            }
            // E29.3 smoke: match lighting over de selectie (E50.3: gedeelde actie).
            if args.contains("--board-match-light"), AppFeatureFlags.matchLightingEnabled {
                PortraitSetActions.matchLighting(
                    selectedPortraits, undoManager: undoManager, reporter: model.setActionReporter
                )
            }
        }
        // Smoke: forceer het rechtermuis-menu op de eerste node (los van --board-select).
        if args.contains("--show-board-menu") {
            model.presentation.boardPortraitMenuID = model.presentation.boardPortraitMenuID
                ?? portraits.first?.persistentModelID
        }
        #endif
    }

    private func fitIfNeeded() {
        guard viewport.width > 0, viewport.height > 0, !portraits.isEmpty else { return }
        // Stop met auto-fitten zodra de gebruiker de camera zelf heeft verzet.
        if let lastFit, camera != lastFit { return }
        camera.fitToContent(contentSize: boardSize, in: viewport)
        lastFit = camera
    }

    // MARK: - Drag (node verplaatsen)

    private func dragGesture(for portrait: Portrait2) -> some Gesture {
        // .global = scherm-space: de node zit ín de camera-scaleEffect, dus de
        // default .local-translatie is al board-space — daar nóg eens door
        // camera.scale delen liet de node ver wegschieten (erger bij uitzoomen).
        // In scherm-space is ÷camera.scale de enige (juiste) correctie.
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                // Draait het gesleepte portret mee in een multi-selectie?
                let groupDrag = selection.count >= 2
                    && selection.contains(portrait.persistentModelID)
                let dragGroup: [Portrait2] = groupDrag ? selectedPortraits : [portrait]

                // Leg startposities eenmalig vast bij het begin van de sleep.
                if dragStartPositions.isEmpty {
                    for p in dragGroup {
                        dragStartPositions[p.persistentModelID] = CGPoint(x: p.boardX, y: p.boardY)
                    }
                }

                // Scherm-delta → board-space (÷ camera-zoom).
                let dx = value.translation.width / camera.scale
                let dy = value.translation.height / camera.scale
                for p in dragGroup {
                    guard let start = dragStartPositions[p.persistentModelID] else { continue }
                    p.boardX = start.x + dx
                    p.boardY = start.y + dy
                }
            }
            .onEnded { _ in
                let groupDrag = selection.count >= 2
                    && selection.contains(portrait.persistentModelID)
                let dragGroup: [Portrait2] = groupDrag ? selectedPortraits : [portrait]
                let before = dragGroup.compactMap { dragStartPositions[$0.persistentModelID] }
                if !before.isEmpty {
                    registerMoveUndo(dragGroup, before: before, name: "Move")
                }
                dragStartPositions = [:]
            }
    }

    // MARK: - Camera (E27.1)
    // Pinch-zoom wordt afgehandeld door CanvasInteractionCatcher (NSEvent
    // .magnify), zodat het ook werkt als er iets geselecteerd is.

    @ViewBuilder
    private var boardShortcutButtons: some View {
        // E27.10: de zoom-sneltoetsen (⌘+/⌘=/⌘−/⌘0) zijn hier weg — die lopen
        // nu via het View-menu + `CanvasZoomEqualsShortcut` (zelfde mechanisme
        // als de editor, zie `body`). Hier alleen nog selectie/organize.
        Group {
            Button("") { selection = Set(portraits.map(\.persistentModelID)) }.keyboardShortcut("a", modifiers: .command)
            // Organize-snelkoppelingen (^⌥): de methodes guarden zelf op selectiegrootte.
            Button("") { tidyUpSelection() }.keyboardShortcut("t", modifiers: [.control, .option])
            Button("") { distributeSelection(.vertical) }.keyboardShortcut("v", modifiers: [.control, .option])
            Button("") { distributeSelection(.horizontal) }.keyboardShortcut("h", modifiers: [.control, .option])
            // UXS-15 (UX16): ⌫ en Esc ontbraken hier terwijl de Banner Studio ze
            // wél had — twee canvassen die anders reageren op dezelfde toets.
            // Verwijderen loopt door de bestaande bevestiging (E46), dus ⌫ opent
            // de confirm i.p.v. direct te wissen.
            Button("") { deleteSelectionViaConfirm() }
                .keyboardShortcut(.delete, modifiers: [])
            Button("") { selection.removeAll() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// UXS-15: ⌫ op de board — zelfde route als het contextmenu, dus mét de
    /// E46-bevestiging. Leeg selectie = niets te doen.
    private func deleteSelectionViaConfirm() {
        let ids = selectedPortraits.map(\.persistentModelID)
        guard !ids.isEmpty else { return }
        model.presentation.confirm = .deletePortraits(ids: ids)
    }

    private func zoom(_ factor: CGFloat) {
        DSMotion.animate(DSMotion.springSmall) { camera.zoomCentered(by: factor) }
    }

    private func fit() {
        DSMotion.animate(DSMotion.springSmall) { camera.fitToContent(contentSize: boardSize, in: viewport) }
    }

    // MARK: - E29.2 batch-toolbar

    /// Zwevende batch-toolbar: past dezelfde Background/Adjust toe op ALLE
    /// geselecteerde portretten. Toont de batch-context ("N selected").
    private var boardBatchBar: some View {
        HStack(spacing: DSSpacing.gap2) {
            Text("\(selection.count) selected")
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.primary)
                // E32.1: het label heeft geen eigen pil-padding zoals de knoppen,
                // dus extra leading zodat het niet tegen de capsule-rand plakt en
                // in lijn ligt met het horizontale ritme van de pillen.
                .padding(.leading, DSSpacing.gap2)

            Divider().frame(height: 16).overlay(DSColor.Foreground.divider)

            // E31.7: Background = dezelfde volledige BackgroundPanel als de
            // single-editor (besluit Thierry: geen aparte inline-swatches),
            // toegepast op ALLE geselecteerde.
            backgroundMenuButton(isOpen: model.presentation.boardBatchMenu == .background,
                                  toggle: { model.presentation.boardBatchMenu = (model.presentation.boardBatchMenu == .background) ? nil : .background },
                                  display: selectedPortraits.first)

            Divider().frame(height: 16).overlay(DSColor.Foreground.divider)

            // E29.3: Match lighting over de selectie (≥2). E50.3: dezelfde
            // `PortraitSetActions` als het raster — automatische doelkeuze
            // (patroon van de set / best belicht), Adjust-laag i.p.v. pixels,
            // toast met Undo via de shell.
            // E32.1: gedeelde compacte pil (SF-Symbol-init) i.p.v. de inline-knop.
            if selection.count >= 2 {
                DSCapsuleToolButton(
                    Image(systemName: "square.resize"),
                    label: "Match framing",
                    size: .compact,
                    action: {
                        PortraitSetActions.matchFraming(
                            selectedPortraits, undoManager: undoManager, reporter: model.setActionReporter
                        )
                    }
                )
                .disabled(model.isSetActionBusy)

                if AppFeatureFlags.matchLightingEnabled {
                    Divider().frame(height: 16).overlay(DSColor.Foreground.divider)

                    DSCapsuleToolButton(
                        Image(systemName: model.isSetActionBusy ? "circle.dotted" : "sun.max"),
                        label: model.isSetActionBusy ? "Matching…" : "Match lighting",
                        size: .compact,
                        action: {
                            PortraitSetActions.matchLighting(
                                selectedPortraits, undoManager: undoManager, reporter: model.setActionReporter
                            )
                        }
                    )
                    .disabled(model.isSetActionBusy)
                }

                Divider().frame(height: 16).overlay(DSColor.Foreground.divider)

                // Figma-pariteit: de 6 uitlijn-assen zitten gevouwen onder één
                // pil (icoon + chevron) die de zwevende uitlijn-capsule opent.
                alignMenuButton

                // Organize: tidy-up + distribute-spacing onder één grid-pil met
                // chevron (zelfde groepeer-patroon als Figma's "Organize").
                organizeMenuButton

                Divider().frame(height: 16).overlay(DSColor.Foreground.divider)
            }

            // Adjust: dezelfde kleurcorrectie op alle geselecteerde (dropdown).
            // E32.1: gedeelde compacte pil — active (menu open) = lime-ring.
            DSCapsuleToolButton(
                Image(systemName: "slider.horizontal.3"),
                label: "Adjust",
                isActive: model.presentation.boardBatchMenu == .adjust,
                size: .compact,
                action: { model.presentation.boardBatchMenu = (model.presentation.boardBatchMenu == .adjust) ? nil : .adjust }
            )
            .overlay(alignment: .top) {
                if model.presentation.boardBatchMenu == .adjust, let first = selectedPortraits.first,
                   let img = NSImage(data: first.cutoutData) {
                    AdjustPanel(
                        source: img,
                        initial: first.adjust,
                        onCommit: { _, after in applyAdjustToAll(after) },
                        maxWidth: 360
                    )
                    .frame(width: 360)
                    .fixedSize(horizontal: false, vertical: true)
                    .dsOutsideClickInside(batchMenuClickScope)
                    .offset(y: DSToolbarSize.compact.height
                              + DSToolbarSize.compact.containerPadding
                              + DSSpacing.gap2)
                    .zIndex(1000)
                    .compositingGroup()
                }
            }
        }
        // E32.1: trailing-tegenhanger van de label-leading, zodat de hover-/
        // active-fill van de laatste pil net zo ver (≈12pt) van de capsule-rand
        // klaart als het leidende label — symmetrisch inclusief hover-state.
        .padding(.trailing, DSSpacing.gap2)
        // E32.1: zelfde solide Card-capsule als de single-editor toolbars
        // (geen glas/rand), compacte maat.
        .dsToolbarCapsule(size: .compact)
        // De bar is het anker; elke dropdown markeert zichzelf als "binnen".
        .dsDismissOnOutsideClick(batchMenuClickScope, isActive: model.presentation.boardBatchMenu != nil) {
            model.presentation.boardBatchMenu = nil
        }
    }

    /// Uitlijn-pil (icoon + chevron). Opent een zwevende capsule met de 6 assen
    /// — de capsule blijft open zodat meerdere uitlijningen na elkaar kunnen.
    private var alignMenuButton: some View {
        DSCapsuleToolButton(
            Image(systemName: "align.horizontal.left.fill"),
            showChevron: true,
            isActive: model.presentation.boardBatchMenu == .align,
            size: .compact,
            action: { model.presentation.boardBatchMenu = (model.presentation.boardBatchMenu == .align) ? nil : .align }
        )
        .overlay(alignment: .top) {
            if model.presentation.boardBatchMenu == .align {
                HStack(spacing: DSToolbarSize.compact.itemSpacing) {
                    alignIcon("align.horizontal.left", .left)
                    alignIcon("align.horizontal.center", .centerH)
                    alignIcon("align.horizontal.right", .right)
                    alignIcon("align.vertical.top", .top)
                    alignIcon("align.vertical.center", .centerV)
                    alignIcon("align.vertical.bottom", .bottom)
                }
                .dsToolbarCapsule(size: .compact)
                .dsOutsideClickInside(batchMenuClickScope)
                .offset(y: DSToolbarSize.compact.height
                          + DSToolbarSize.compact.containerPadding
                          + DSSpacing.gap2)
                .zIndex(10)
            }
        }
    }

    private func alignIcon(_ symbol: String, _ axis: BoardAlignAxis) -> some View {
        DSCapsuleToolButton(Image(systemName: symbol), size: .compact,
                            action: { alignSelection(axis) })
    }

    /// Organize-pil (grid-icoon + chevron): tidy-up + distribute-spacing in een
    /// rij-dropdown (zelfde menu-rij-stijl als het rechtermuis-menu).
    private var organizeMenuButton: some View {
        DSCapsuleToolButton(
            Image(systemName: "square.grid.2x2"),
            label: "Organize",
            showChevron: true,
            isActive: model.presentation.boardBatchMenu == .organize,
            size: .compact,
            action: { model.presentation.boardBatchMenu = (model.presentation.boardBatchMenu == .organize) ? nil : .organize }
        )
        .overlay(alignment: .top) {
            if model.presentation.boardBatchMenu == .organize {
                DSContextMenuPanel(minWidth: 240) {
                    DSMenuRow("Tidy up", icon: "square.grid.2x2", shortcut: "⌃⌥T") {
                        model.presentation.boardBatchMenu = nil; tidyUpSelection()
                    }
                    DSMenuRow("Distribute vertical spacing", icon: "rectangle.split.1x2",
                              shortcut: "⌃⌥V", disabled: selection.count < 3) {
                        model.presentation.boardBatchMenu = nil; distributeSelection(.vertical)
                    }
                    DSMenuRow("Distribute horizontal spacing", icon: "rectangle.split.2x1",
                              shortcut: "⌃⌥H", disabled: selection.count < 3) {
                        model.presentation.boardBatchMenu = nil; distributeSelection(.horizontal)
                    }
                }
                .fixedSize()
                .dsOutsideClickInside(batchMenuClickScope)
                .offset(y: DSToolbarSize.compact.height
                          + DSToolbarSize.compact.containerPadding
                          + DSSpacing.gap2)
                .zIndex(10)
            }
        }
    }

    /// E31.7: gedeelde "Background"-knop met de volledige `BackgroundPanel` als
    /// zwevende dropdown — dezelfde panel-UI als de single-editor. `display`
    /// levert de selectie-state + Original/custom-bron; de apply gaat via
    /// `onApply` naar ALLE geselecteerde portretten.
    private func backgroundMenuButton(
        isOpen: Bool, toggle: @escaping () -> Void, display: Portrait2?
    ) -> some View {
        // E32.1: gedeelde compacte pil (SF-Symbol-init); active (open) = lime-ring.
        DSCapsuleToolButton(
            Image(systemName: "photo"),
            label: "Background",
            isActive: isOpen,
            size: .compact,
            action: toggle
        )
        .overlay(alignment: .top) {
            if isOpen {
                BackgroundPanel(portrait: display, onApply: { applyBackgroundToAll($0) }, presentation: model.presentation, entitlement: entitlement)
                    .padding(DSSpacing.gap4)
                    // 440: zelfde breedte als de editor-popover (Notion-stijl
                    // tab-paneel, 4-koloms grid).
                    .frame(width: 440)
                    .fixedSize(horizontal: false, vertical: true)
                    .dsMenuSurface()
                    .dsOutsideClickInside(batchMenuClickScope)
                    .offset(y: DSToolbarSize.compact.height
                              + DSToolbarSize.compact.containerPadding
                              + DSSpacing.gap2)
                    .zIndex(1000)
                    .compositingGroup()
            }
        }
    }

    /// E29.2/E31.7: pas dezelfde achtergrond toe op alle geselecteerde portretten.
    private func applyBackgroundToAll(_ background: PortraitBackground) {
        let targets = selectedPortraits
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Background")
        for p in targets {
            let before = p.background
            guard before != background else { continue }
            p.setBackground(background)
            ReversibleChange.register(
                undoManager, target: p,
                from: before, to: background, actionName: "Background"
            ) { portrait, bg in
                portrait.setBackground(bg)
            }
        }
        undoManager?.endUndoGrouping()
    }

    private func undoableSetBackground(_ background: PortraitBackground, on node: Portrait2) {
        let before = node.background
        guard before != background else { return }
        node.setBackground(background)
        ReversibleChange.register(
            undoManager, target: node,
            from: before, to: background, actionName: "Background"
        ) { portrait, bg in
            portrait.setBackground(bg)
        }
    }

    private func alignSelection(_ axis: BoardAlignAxis) {
        let targets = selectedPortraits
        guard targets.count >= 2 else { return }
        let before = targets.map { CGPoint(x: $0.boardX, y: $0.boardY) }
        let minX = targets.map(\.boardX).min()!, maxX = targets.map(\.boardX).max()!
        let minY = targets.map(\.boardY).min()!, maxY = targets.map(\.boardY).max()!
        DSMotion.animate(DSMotion.springSmall) {
            switch axis {
            case .left:    targets.forEach { $0.boardX = minX }
            case .centerH: targets.forEach { $0.boardX = (minX + maxX) / 2 }
            case .right:   targets.forEach { $0.boardX = maxX }
            case .top:     targets.forEach { $0.boardY = minY }
            case .centerV: targets.forEach { $0.boardY = (minY + maxY) / 2 }
            case .bottom:  targets.forEach { $0.boardY = maxY }
            }
        }
        registerMoveUndo(targets, before: before, name: "Align")
    }

    private func tidyUpSelection() {
        let targets = selectedPortraits.sorted {
            $0.boardY != $1.boardY ? $0.boardY < $1.boardY : $0.boardX < $1.boardX
        }
        guard targets.count >= 2 else { return }
        let before = targets.map { CGPoint(x: $0.boardX, y: $0.boardY) }
        let cols = max(1, Int(ceil(sqrt(Double(targets.count)))))
        let rows = Int(ceil(Double(targets.count) / Double(cols)))
        let cx = targets.map(\.boardX).reduce(0, +) / Double(targets.count)
        let cy = targets.map(\.boardY).reduce(0, +) / Double(targets.count)
        let gridW = Double(cols) * Double(cardSide) + Double(cols - 1) * Double(gap)
        let gridH = Double(rows) * Double(cellHeight) + Double(rows - 1) * Double(gap)
        let ox = cx - gridW / 2 + Double(cardSide) / 2
        let oy = cy - gridH / 2 + Double(cellHeight) / 2
        DSMotion.animate(DSMotion.springSmall) {
            for (i, p) in targets.enumerated() {
                p.boardX = ox + Double(i % cols) * (Double(cardSide) + Double(gap))
                p.boardY = oy + Double(i / cols) * (Double(cellHeight) + Double(gap))
            }
        }
        registerMoveUndo(targets, before: before, name: "Tidy Up")
    }

    /// Verdeel de selectie met gelijke tussenruimte langs één as. Houdt de uiterste
    /// twee vast en zet de rest op gelijke afstand ertussen (Figma "distribute
    /// spacing"; voor gelijke kaartmaten = gelijke center-afstand). Vereist ≥3.
    private func distributeSelection(_ axis: BoardDistributeAxis) {
        let targets = selectedPortraits
        guard targets.count >= 3 else { return }
        let before = targets.map { CGPoint(x: $0.boardX, y: $0.boardY) }
        DSMotion.animate(DSMotion.springSmall) {
            switch axis {
            case .horizontal:
                let sorted = targets.sorted { $0.boardX < $1.boardX }
                let lo = sorted.first!.boardX, hi = sorted.last!.boardX
                let step = (hi - lo) / Double(sorted.count - 1)
                for (i, p) in sorted.enumerated() { p.boardX = lo + Double(i) * step }
            case .vertical:
                let sorted = targets.sorted { $0.boardY < $1.boardY }
                let lo = sorted.first!.boardY, hi = sorted.last!.boardY
                let step = (hi - lo) / Double(sorted.count - 1)
                for (i, p) in sorted.enumerated() { p.boardY = lo + Double(i) * step }
            }
        }
        registerMoveUndo(targets, before: before, name: "Distribute")
    }

    /// Gedeelde, gegroepeerde undo voor een batch-verplaatsing (align/tidy/distribute):
    /// één undo-groep, per portret een `BoardMoveUndo` van oud→nieuw.
    private func registerMoveUndo(_ targets: [Portrait2], before: [CGPoint], name: String) {
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName(name)
        for (i, p) in targets.enumerated() {
            BoardMoveUndo.register(undoManager, portrait: p,
                                   from: before[i], to: CGPoint(x: p.boardX, y: p.boardY))
        }
        undoManager?.endUndoGrouping()
    }

    /// E29.2: pas dezelfde Adjust-laag toe op alle geselecteerde portretten.
    /// E50.3: set-brede actie → `bumpRevision()` i.p.v. `touch()` (thumbs
    /// verversen, rasterorde blijft), ook in de undo/redo.
    private func applyAdjustToAll(_ adjust: PortraitAdjust) {
        let targets = selectedPortraits
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Adjust")
        for p in targets {
            let before = p.adjust
            p.adjust = adjust
            p.bumpRevision()
            AdjustUndo.register(
                undoManager, target: p,
                apply: { [p] adj in
                    p.adjust = adj
                    p.bumpRevision()
                },
                undoTo: before, redoTo: adjust, actionName: "Adjust"
            )
        }
        undoManager?.endUndoGrouping()
    }

    // MARK: - E30.1 in-place editen op één node

    /// E31.7: top-toolbar bij precies één selectie = dezelfde frame-lokale
    /// `CanvasActionToolbar` als de single-editor, getrimd tot board-relevante
    /// controls (Frame ▾ met Shape + Flip · Background-panel). Auto-frame/Grid
    /// (editor-only transform/overlay) zijn verborgen. Color-sliders zitten
    /// onder "Adjust" in de bottom-capsule — net als de editor.
    private func singleEditTopBar(_ node: Portrait2) -> some View {
        CanvasActionToolbar(
            onFlip: { flipNode(node) },
            frameShape: node.frameShape,
            onSetFrameShape: { setNodeFrameShape($0, node) },
            activeMenu: boardCanvasMenuBinding,
            gridEnabled: .constant(false),
            showFramingActions: false,
            showGrid: false,
            background: { BackgroundPanel(portrait: node, onApply: { undoableSetBackground($0, on: node) }, presentation: model.presentation, entitlement: entitlement) }
        )
    }

    /// E31.7: zet de frame-vorm van één board-node (zelfde als EditorView).
    private func setNodeFrameShape(_ shape: ExportShape, _ node: Portrait2) {
        DSMotion.animate(DSMotion.springSmall) { node.frameShape = shape }
        node.touch()
    }

    /// E31.7: bottom-toolbar bij precies één selectie = dezelfde `DSBottomToolbar`-
    /// capsule als de single-editor, met de GEDEELDE items (Enhance · Adjust ·
    /// Effects · Face · Hair · Clothing). Het actieve paneel zweeft als dropdown
    /// erboven. Enhance = AI één-tik; Adjust = compacte color-sliders.
    private func singleEditBottomBar(_ node: Portrait2) -> some View {
        VStack(spacing: DSSpacing.gap2) {
            // Actief paneel boven de balk.
            if let tool = editTool,
               tool.isEnabled(remote: entitlement.featureFlags),
               let images = singleEditImages.images(for: node) {
                let base = images.base
                Group {
                    switch tool {
                    case .edit:
                        DSEditPanel(title: "Enhance", maxWidth: 420) {
                            EditColorPanel(
                                source: base,
                                previewBackdrop: images.backdrop,
                                initial: node.adjust,
                                onCommit: { _, after in applyAdjustToAll(after) },
                                onRetouch: { retouchNode(node) },
                                presentation: model.presentation,
                                showRetouch: true,
                                showAutoEnhance: false,
                                showSliders: false
                            )
                        }
                    case .adjust:
                        AdjustPanel(
                            source: base,
                            initial: node.adjust,
                            onCommit: { _, after in applyAdjustToAll(after) },
                            maxWidth: 420
                        )
                        .id(node.persistentModelID)
                    case .effects:
                        EffectsPanel(baseImage: base, entitlement: entitlement, portrait: node,
                                     presentation: model.presentation,
                                     onApply: { await undoableApplyEffectToNode($0, $1, node) })
                            .id(node.persistentModelID)
                    case .clothing:
                        ClothesPanel(baseImage: base, entitlement: entitlement,
                                     onApply: { await undoableApplyToNode($0, node, actionName: "Change clothing") })
                            .id(node.persistentModelID)
                    case .hair:
                        HairPanel(baseImage: base, entitlement: entitlement,
                                  onApply: { await undoableApplyToNode($0, node, actionName: "Change hair") })
                            .id(node.persistentModelID)
                    case .face:
                        DSEditPanel(
                            title: "Face",
                            credits: CreditMeter.chipLabel(for: .generativeStandard),
                            maxWidth: 420
                        ) {
                            FaceActionsPanel(
                                baseImage: base,
                                entitlement: entitlement,
                                onApply: { await undoableApplyToNodePreservingAlpha($0, node, actionName: "Face edit") },
                                isPro: entitlement.isProActive
                            )
                            .id(node.persistentModelID)
                        }
                    default:
                        EmptyView()
                    }
                }
                .frame(width: 420)
                .fixedSize(horizontal: false, vertical: true)
                // Elk child-paneel heeft z'n eigen dsMenuSurface via DSEditPanel.
                .zIndex(1000)
                .compositingGroup()
                .transition(.dsScaleFade(anchor: .bottom, reduceMotion: reduceMotion))
            }

            DSBottomToolbar(items: boardToolbarItems, selection: $editTool)
        }
        .dsMotion(DSMotion.fast, value: editTool)
    }

    /// E30.1: een cloud/flip-resultaat op de node toepassen via dezelfde pipeline
    /// als de editor (re-isolatie bij volle achtergrond) → cutoutData + thumbnail.
    private func applyToNode(_ image: NSImage, _ node: Portrait2) async {
        model.select(node)
        await model.applyEffectResult(image)
        editTool = nil
    }

    /// Face-edits: bewaart de cutout-alpha als masker i.p.v. Vision opnieuw.
    private func applyToNodePreservingAlpha(_ image: NSImage, _ node: Portrait2) async {
        model.select(node)
        await model.applyEffectResult(image, preserveSourceAlpha: true)
        editTool = nil
    }

    /// Zelfde als applyToNode maar registreert ook een undo/redo-entry zodat
    /// Cmd+Z de bewerking terugdraait en Cmd+Shift+Z 'm hertoepast.
    private func undoableApplyToNode(_ image: NSImage, _ node: Portrait2, actionName: String) async {
        guard let before = NSImage(data: node.cutoutData) else {
            await applyToNode(image, node)
            return
        }
        await applyToNode(image, node)
        ImageEnhanceUndo.register(
            undoManager, target: node,
            apply: { [model] img in
                model.select(node)
                await model.applyEffectResult(img)
            },
            undoTo: before, redoTo: image, actionName: actionName
        )
    }

    /// Effects-variant van `undoableApplyToNode`: draagt de kadrering van de
    /// wissel mee (Sticker-fix — die-cut → content-fit) en keert 'm om bij undo.
    private func undoableApplyEffectToNode(_ image: NSImage, _ framing: EffectFraming, _ node: Portrait2) async {
        model.select(node)
        guard let before = NSImage(data: node.cutoutData) else {
            await model.applyEffectResult(image, framing: framing)
            editTool = nil
            return
        }
        await model.applyEffectResult(image, framing: framing)
        editTool = nil
        ImageEnhanceUndo.register(
            undoManager, target: node,
            apply: { [model] img in
                model.select(node)
                await model.applyEffectResult(img, framing: img === image ? framing : framing.inverse)
            },
            undoTo: before, redoTo: image, actionName: "Apply effect"
        )
    }

    private func undoableApplyToNodePreservingAlpha(_ image: NSImage, _ node: Portrait2, actionName: String) async {
        guard let before = NSImage(data: node.cutoutData) else {
            await applyToNodePreservingAlpha(image, node)
            return
        }
        await applyToNodePreservingAlpha(image, node)
        ImageEnhanceUndo.register(
            undoManager, target: node,
            apply: { [model] img in
                model.select(node)
                await model.applyEffectResult(img, preserveSourceAlpha: true)
            },
            undoTo: before, redoTo: image, actionName: actionName
        )
    }

    /// Spiegelt de cutout van de node horizontaal (zelfde transform als editor).
    /// Decode + flip-render draaien off-main; alleen de apply (SwiftData) op main.
    private func flipNode(_ node: Portrait2) {
        let data = node.cutoutData
        Task {
            let box = await Task.detached(priority: .userInitiated) { () -> SendableCGImage? in
                guard let cg = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let space = CGColorSpace(name: CGColorSpace.sRGB),
                      let ctx = CGContext(
                        data: nil, width: cg.width, height: cg.height,
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      ) else { return nil }
                ctx.translateBy(x: CGFloat(cg.width), y: 0)
                ctx.scaleBy(x: -1, y: 1)
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                return ctx.makeImage().map(SendableCGImage.init)
            }.value
            guard let out = box?.cgImage else { return }
            await undoableApplyToNode(
                NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height)),
                node, actionName: "Flip"
            )
        }
    }

    /// One-click retouch op de node (lokaal, zelfde enhancer als de editor).
    /// Decode + enhance draaien off-main; alleen de apply (SwiftData) op main.
    private func retouchNode(_ node: Portrait2) {
        let data = node.cutoutData
        Task {
            let box = await Task.detached(priority: .userInitiated) { () -> SendableCGImage? in
                guard let cg = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let out = PortraitEnhancer.magicRetouch(cg) else { return nil }
                return SendableCGImage(cgImage: out)
            }.value
            guard let out = box?.cgImage else { return }
            await undoableApplyToNode(
                NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height)),
                node, actionName: "One click retouch"
            )
        }
    }

    private var hud: some View {
        VStack {
            Spacer()
            HStack {
                Text(exportStatus ?? (selection.isEmpty
                     ? "\(portraits.count) portraits — click to select, double-click to edit"
                     : "\(selection.count) selected"))
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(selection.isEmpty && exportStatus == nil
                                     ? DSColor.Foreground.muted : DSColor.Foreground.primary)
                Spacer()
                // UXS-6/UXS-16: gedeelde chip. De board toont "Fit" i.p.v. een
                // percentage — hier is er geen vaste kaartmaat om tegen af te
                // zetten, dus een percentage zou nergens op slaan.
                DSCanvasZoomChip(title: "Fit", action: fit)
            }
        }
    }
}

/// E27.6 (Tier 1): één board-node als losse, `Equatable` view. De camera-transform
/// staat op de container (`boardCanvas`), niet hier — dus bij een pan/zoom-only
/// change blijft een node `==` aan z'n vorige zelf en slaat SwiftUI z'n body over
/// (de SwiftUI-tegenhanger van "Figma verandert alleen de camera-matrix, niet de
/// node-texture"). Gestures/hover hangen BUITEN deze view (in `BoardView`) zodat hun
/// verse closures de equatable-skip niet breken.
private struct BoardNodeView: View, Equatable {
    let thumbnail: NSImage?
    /// Origineel als achtergrondLAAG (Original-modus / Portrait-blur), al
    /// gedecodeerd + downscaled door de ThumbnailStore. nil = geen Original-laag.
    /// Wordt op DEZELFDE scaledToFit+padding-rect als de cutout-thumb getekend,
    /// zodat het originele onderwerp achter het cutout-onderwerp registreert.
    let backgroundOriginalImage: NSImage?
    let isSelected: Bool
    let frameShape: ExportShape
    let name: String
    let role: String
    let backgroundColorHex: String?
    let backgroundImageData: Data?
    /// Portrait-modus (achtergrond-blur) — vervaagt de custom-achtergrond op de board.
    let portraitBlur: Bool
    /// `Portrait2.revision` — O(1) wijzigings-token voor de (dure) bg-image-`Data`:
    /// `setBackground` bumpt 'm, dus we hoeven nooit de bytes te vergelijken.
    let contentVersion: Int
    let cardSide: CGFloat
    let labelGap: CGFloat
    let labelHeight: CGFloat
    let cellHeight: CGFloat

    /// Goedkope, O(1) gelijkheid — `==` draait O(zichtbaar)× per camera-frame, dus
    /// GEEN byte-vergelijking van `backgroundImageData` (dat rijdt op `contentVersion`)
    /// en de thumbnail vergelijken we op identiteit (de cache geeft instance-stabiliteit).
    static func == (lhs: BoardNodeView, rhs: BoardNodeView) -> Bool {
        lhs.isSelected == rhs.isSelected
            && lhs.thumbnail === rhs.thumbnail
            // Op identiteit (cache-stabiel) — vangt zowel modus-wissel (nil↔beeld)
            // als de async decode-voltooiing, net als `thumbnail`.
            && lhs.backgroundOriginalImage === rhs.backgroundOriginalImage
            && lhs.frameShape == rhs.frameShape
            && lhs.name == rhs.name
            && lhs.role == rhs.role
            && lhs.backgroundColorHex == rhs.backgroundColorHex
            && lhs.portraitBlur == rhs.portraitBlur
            && lhs.contentVersion == rhs.contentVersion
    }

    private var clip: AnyShape {
        frameShape == .circle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: DSRadius.xl4))
    }

    var body: some View {
        VStack(spacing: labelGap) {
            cardSurface
                .frame(width: cardSide, height: cardSide)
                // E29.1: selectie-ring (lime) om de geselecteerde nodes.
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: DSRadius.xl4)
                            .strokeBorder(DSColor.Action.primary, lineWidth: 3)
                            .padding(-4)
                    }
                }
            VStack(spacing: 2) {
                Text(name.isEmpty ? "Untitled" : name)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(isSelected ? DSColor.Action.primaryForeground : DSColor.Foreground.primary)
                    .lineLimit(1)
                if !role.isEmpty {
                    Text(role)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .lineLimit(1)
                }
            }
            .frame(height: labelHeight)
        }
        .frame(width: cardSide, height: cellHeight)
    }

    /// Kaart-surface met het cutout-beeld, geclipt tot de frame-vorm (mini-
    /// DSCanvasCard, zonder de transform-machinerie).
    @ViewBuilder
    private var cardSurface: some View {
        ZStack {
            DSColor.Background.card
            // E29.2: de gekozen achtergrondkleur achter de cutout → batch-
            // Background is meteen zichtbaar op de board (WYSIWYG voor kleur).
            if let hex = backgroundColorHex, let c = Color(hexRGB: hex) {
                c
            }
            // E29.2: ook de gekozen achtergrondafbeelding achter de cutout, zodat
            // een batch-Image-Background meteen WYSIWYG op de board verschijnt
            // (spiegelt EditorView.backgroundLayer; Color.clear voorkomt dat de
            // intrinsieke uploadmaat de kaartlayout in lekt).
            if let data = backgroundImageData, let image = NSImage(data: data) {
                Color.clear
                    .overlay { Image(nsImage: image).resizable().scaledToFill() }
                    .clipped()
                    // Portrait: vervaag de custom-achtergrond (de onderwerp-thumb erboven blijft scherp).
                    .blur(radius: portraitBlur ? BackgroundBlur.canvasRadius(side: cardSide) : 0)
            }
            // Original-modus: de originele foto op EXACT dezelfde scaledToFit+padding-
            // rect als de cutout-thumb → het originele onderwerp registreert achter het
            // scherpe onderwerp (niet dubbel; cutout en origineel delen de aspect-ratio).
            // Portrait: vervaagd (onderwerp-thumb erboven blijft scherp).
            else if let original = backgroundOriginalImage {
                Image(nsImage: original)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .padding(cardSide * 0.08)
                    .blur(radius: portraitBlur ? BackgroundBlur.canvasRadius(side: cardSide) : 0)
            }
            // E27.5: gecachete, verkleinde thumbnail (geen re-decode per frame),
            // E30.2 mét de niet-destructieve Adjust-laag erop (WYSIWYG). De cache is
            // (id, revision)-gekeyd (E27.6 Tier 0), dus in-place-edits verversen vanzelf.
            if let thumbnail {
                // E27.6 (Tier 4): `.medium` i.p.v. `.high` — de thumb is al klein
                // (~2× kaartmaat) dus op kaartmaat onzichtbaar verschil, maar de GPU
                // hersamplet 'm goedkoper terwijl de camera in-/uitzoomt.
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .padding(cardSide * 0.08)
            }
        }
        .clipShape(clip)
        .overlay(clip.stroke(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
    }
}

private enum BoardAlignAxis {
    case left, centerH, right, top, centerV, bottom
}

private enum BoardDistributeAxis {
    case horizontal, vertical
}

/// E27.4: undo/redo voor een board-node-verplaatsing (zelfde genest-register-
/// patroon als TransformUndo: de undo herstelt de oude positie én registreert de
/// redo).
enum BoardMoveUndo {
    @MainActor
    static func register(_ undoManager: UndoManager?, portrait: Portrait2, from old: CGPoint, to new: CGPoint) {
        guard old != new else { return }
        ReversibleChange.register(
            undoManager, target: portrait, from: old, to: new, actionName: "Move portrait"
        ) { target, point in
            target.boardX = point.x
            target.boardY = point.y
        }
    }
}

/// Gedecodeerde cutout + origineel van de single-edit-node, gememoïseerd op
/// (node, revision). Referentietype zodat de memo tijdens een body-pass mag
/// vullen zonder @State-mutatie; `touch()` bumpt `revision` bij elke edit,
/// dus een nieuwe stand decodeert vers (zelfde aanname als ThumbnailStore).
final class SingleEditImageMemo {
    private var key: (id: PersistentIdentifier, revision: Int)?
    private var cached: (base: NSImage, backdrop: NSImage?)?

    func images(for node: Portrait2) -> (base: NSImage, backdrop: NSImage?)? {
        let id = node.persistentModelID
        if let key, key.id == id, key.revision == node.revision, let cached {
            return cached
        }
        guard let base = NSImage(data: node.cutoutData) else {
            key = nil
            cached = nil
            return nil
        }
        let images = (base: base, backdrop: node.originalData.flatMap { NSImage(data: $0) })
        key = (id, node.revision)
        cached = images
        return images
    }
}
