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
    /// Dezelfde bron als de sidebar (E05.4): alle portretten, jongste eerst.
    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
    /// E30.1: dezelfde edit-pipeline als de editor — bij één-selectie zetten we
    /// `model.selectedPortrait` op de node en hergebruiken we model.applyEffectResult
    /// (cloud-re-isolatie!) / commitAdjust i.p.v. die logica te dupliceren.
    let model: ShellModel
    let entitlement: EntitlementModel
    /// Dubbelklik op een node → openen (selecteren) in de editor.
    let onOpen: (Portrait2) -> Void

    @Environment(\.undoManager) private var undoManager
    /// Delete-actie van het rechtermuis-menu (zelfde modelContext-pad als de sidebar).
    @Environment(\.modelContext) private var modelContext

    // E30.1 / E31.7: actief bottom-tool bij ÉÉN geselecteerde node (in-place
    // editen op de board). Dezelfde `EditorTool` als de single-editor zodat de
    // board exact dezelfde capsule-items/labels/iconen toont.
    @State private var editTool: EditorTool?
    // E31.7: stuurt de Frame/Background-dropdowns van de gedeelde
    // `CanvasActionToolbar` in de board single-select top-bar.
    @State private var canvasMenu: CanvasToolbarMenu?

    /// De enige geselecteerde node (nil bij 0 of ≥2) — de in-place-edit-target.
    private var selectedNode: Portrait2? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return portraits.first { $0.persistentModelID == id }
    }

    /// E27.6 (Tier 3): off-main thumbnail-store — decodeert elke cutout één keer
    /// per (id, updatedAt, maat) op een achtergrond-Task (geen main-thread-hitch),
    /// (id, updatedAt)-gekeyd zodat edits vanzelf verversen, met FIFO-eviction tegen
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

    // Drag-state (board-space).
    @State private var dragStart: CGPoint?

    // E29.1: multi-select op de board.
    @State private var selection: Set<PersistentIdentifier> = []
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
    @State private var menuTarget: Portrait2?
    @State private var renameTargets: [Portrait2] = []
    @State private var deleteTargets: [Portrait2] = []
    /// Bulk-export-status (board heeft geen shell-toast) → getoond in de HUD.
    @State private var exportStatus: String?

    // E29.2: batch-toolbar (open dropdown) + de geselecteerde portretten.
    @State private var batchMenu: BatchMenu?
    // E29.3: loopt tijdens de "Match lighting"-normalisatie over de selectie.
    @State private var isMatchingLight = false
    private enum BatchMenu: Hashable { case background, adjust }

    private var selectedPortraits: [Portrait2] {
        portraits.filter { selection.contains($0.persistentModelID) }
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
        // Top-level GeometryReader = de echte canvas-slot-maat (de vaste board-
        // maat lekt zo niet de viewport-meting in).
        GeometryReader { geo in
            ZStack {
                DSColor.Background.app

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
                        .background {
                            CanvasInteractionCatcher(
                                camera: $camera,
                                chromeHovered: batchMenu != nil || canvasMenu != nil
                            )
                            boardShortcutButtons
                        }
                }

                hud
            }
            .frame(width: geo.size.width, height: geo.size.height)
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
                    } else if let node = selectedNode {
                        singleEditTopBar(node)
                            // Horizontaal gecentreerd boven de geselecteerde node.
                            // Inverse van visibleBoardRect-transform: het overlay-nulpunt
                            // ligt op vpMidden, dus offset = scale·(boardX−boardMidden)+cameraOffset.
                            .offset(x: camera.scale * (node.boardX - boardSize.width / 2)
                                + camera.offset.width)
                    }
                }
                .padding(.top, 70)
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
                if let target = menuTarget {
                    contextMenuOverlay(target)
                }
            }
            // Rename-modal (gedeelde RenameSheet) — bij ≥2 targets zet Save dezelfde
            // naam + rol op álle geselecteerde portretten.
            .sheet(isPresented: Binding(
                get: { !renameTargets.isEmpty },
                set: { if !$0 { renameTargets = [] } }
            )) {
                if !renameTargets.isEmpty { RenameSheet(portraits: renameTargets) }
            }
            // Delete met bevestiging (zelfde modelContext-pad als de sidebar);
            // bij ≥2 targets verwijdert het de hele selectie.
            .confirmationDialog(
                deleteTargets.count >= 2 ? "Delete \(deleteTargets.count) portraits?" : "Delete this portrait?",
                isPresented: Binding(
                    get: { !deleteTargets.isEmpty },
                    set: { if !$0 { deleteTargets = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    for target in deleteTargets {
                        selection.remove(target.persistentModelID)
                        modelContext.delete(target)
                    }
                    deleteTargets = []
                }
                Button("Cancel", role: .cancel) { deleteTargets = [] }
            } message: {
                Text("This can't be undone.")
            }
            .onAppear { viewport = geo.size; assignInitialLayout(); fitIfNeeded(); debugSeedSelection() }
            .onChange(of: geo.size) { _, s in viewport = s; fitIfNeeded() }
            // @Query laadt ná de eerste render → layout + fit zodra de set binnen
            // is; `didInitialFit` latcht pas bij een niet-lege set.
            .onChange(of: portraits.count) { _, _ in assignInitialLayout(); fitIfNeeded() }
            // E30.1: één-selectie → richt de gedeelde edit-pipeline op die node;
            // bij 0 of ≥2 sluit het bottom-tool-paneel.
            .onChange(of: selection) { _, sel in
                // Sluit altijd alle dropdowns bij selectie-wissel — anders
                // heropen de batch-bar met een nog-open dropdown.
                batchMenu = nil
                canvasMenu = nil
                if sel.count == 1, let id = sel.first,
                   let node = portraits.first(where: { $0.persistentModelID == id }) {
                    model.select(node)
                } else {
                    editTool = nil
                }
            }
        }
    }

    // MARK: - Board-canvas (absolute node-posities)

    private var boardCanvas: some View {
        ZStack(alignment: .topLeading) {
            // Onzichtbaar vlak dat de board-maat bepaalt (de nodes positioneren
            // hierop absoluut). E29.1: sleep = marquee-selectie, tik = deselect-all.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selection.removeAll() }
                .gesture(marqueeGesture)

            // E27.5: virtualisatie — alleen nodes die in (of net buiten) de
            // zichtbare viewport vallen, renderen. Scheelt views + werk bij pan/
            // zoom op een grote set.
            ForEach(visibleNodes(), id: \.portrait.persistentModelID) { item in
                let p = item.portrait
                // E27.6 (Tier 1): de node-visuals zitten in een losse, `Equatable`
                // view → een pan/zoom-only change laat 'm `==` blijven en SwiftUI
                // slaat z'n body over. Gestures + hover hangen BUITEN `.equatable()`
                // (verse closures zouden de skip anders breken); de camera-
                // afhankelijke drag-math blijft in `BoardView`.
                BoardNodeView(
                    thumbnail: thumbs.thumbnail(for: p, maxDimension: cardSide * 2),
                    isSelected: selection.contains(p.persistentModelID),
                    frameShape: p.frameShape,
                    name: p.name,
                    role: p.role,
                    backgroundColorHex: p.backgroundColorHex,
                    backgroundImageData: p.backgroundImageData,
                    portraitBlur: p.portraitBlur,
                    contentVersion: p.updatedAt,
                    cardSide: cardSide,
                    labelGap: labelGap,
                    labelHeight: labelHeight,
                    cellHeight: cellHeight
                )
                .equatable()
                .contentShape(Rectangle())
                .dsHoverHighlight(cornerRadius: DSRadius.xl4)
                // E29.1: dubbelklik = openen in de editor; enkelklik = selecteren
                // (cmd/shift = toevoegen/afhalen). Sleep = node verplaatsen (E27.4).
                .onTapGesture(count: 2) { onOpen(p) }
                .onTapGesture { tapNode(p) }
                // Rechtermuis → hetzelfde DS-menu als de sidebar. Selecteert de
                // node eerst als 'ie nog niet in de selectie zit (Finder-gedrag),
                // zodat "Export N portraits…" alleen verschijnt bij een echte
                // multi-selectie; binnen een bestaande ≥2-selectie blijft die staan.
                .onRightClick {
                    if !selection.contains(p.persistentModelID) { selection = [p.persistentModelID] }
                    menuTarget = p
                }
                .gesture(dragGesture(for: p))
                .position(x: item.center.x, y: item.center.y)
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

    /// E29.1: marquee — sleep op de lege board spant een selectie-rechthoek;
    /// nodes waarvan het midden erin valt worden geselecteerd (cmd/shift =
    /// toevoegen aan de bestaande selectie). De selectie loopt live mee tijdens
    /// de sleep (niet pas bij loslaten): bij het eerste frame leggen we de
    /// basis vast (additief → huidige selectie, anders leeg) en elke frame
    /// rekenen we de hits opnieuw tegen die vaste basis.
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if marquee == nil {
                    let additive = NSEvent.modifierFlags.contains(.command)
                        || NSEvent.modifierFlags.contains(.shift)
                    marqueeBase = additive ? selection : []
                }
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
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

    /// E29.1: enkelklik op een node — cmd/shift togglet 'm in/uit de selectie;
    /// anders selecteer alléén deze node.
    private func tapNode(_ portrait: Portrait2) {
        let id = portrait.persistentModelID
        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    // MARK: - Rechtermuis-context-menu (pariteit met de sidebar, E24.22)

    /// Het zwevende DS-menu + de dismiss-scrim, gepositioneerd onder de node.
    @ViewBuilder
    private func contextMenuOverlay(_ target: Portrait2) -> some View {
        let anchor = menuAnchor(for: target)
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { menuTarget = nil }
            nodeContextMenu(for: target)
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
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            if bulk {
                menuRow("Rename \(n) portraits", icon: "pencil") {
                    menuTarget = nil; renameTargets = selectedPortraits
                }
                menuRow("Export \(n) portraits", icon: "square.and.arrow.up.on.square") {
                    menuTarget = nil; bulkExport()
                }
                Divider().padding(.vertical, 2)
                menuRow("Delete \(n) portraits", icon: "trash", destructive: true) {
                    menuTarget = nil; deleteTargets = selectedPortraits
                }
            } else {
                menuRow("Rename", icon: "pencil") { menuTarget = nil; renameTargets = [portrait] }
                menuRow("Export…", icon: "square.and.arrow.up") {
                    menuTarget = nil; model.select(portrait); model.exportCurrentPortrait()
                }
                Divider().padding(.vertical, 2)
                menuRow("Delete", icon: "trash", destructive: true) { menuTarget = nil; deleteTargets = [portrait] }
            }
        }
        .padding(DSMenuLayout.listInset)
        // Past zich aan de inhoud aan (de bulk-labels zijn langer), met een vloer
        // van 190 zodat het enkel-menu niet te smal wordt. `.fixedSize()` in
        // `contextMenuOverlay` krimpt naar deze ideale breedte → de labels passen
        // precies, zonder vaste overbreedte.
        .frame(minWidth: 190, alignment: .leading)
        .dsMenuSurface()
    }

    private func menuRow(_ title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap2) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium)).frame(width: 16)
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
            // E29.3 smoke: match lighting over de selectie.
            if args.contains("--board-match-light") { matchLightingSelection() }
        }
        // Smoke: forceer het rechtermuis-menu op de eerste node (los van --board-select).
        if args.contains("--show-board-menu") { menuTarget = menuTarget ?? portraits.first }
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
                if dragStart == nil {
                    dragStart = CGPoint(x: portrait.boardX, y: portrait.boardY)
                }
                guard let start = dragStart else { return }
                // Scherm-delta → board-space (÷ camera-zoom).
                portrait.boardX = start.x + value.translation.width / camera.scale
                portrait.boardY = start.y + value.translation.height / camera.scale
            }
            .onEnded { _ in
                if let start = dragStart {
                    BoardMoveUndo.register(
                        undoManager, portrait: portrait,
                        from: start, to: CGPoint(x: portrait.boardX, y: portrait.boardY)
                    )
                }
                dragStart = nil
            }
    }

    // MARK: - Camera (E27.1)
    // Pinch-zoom wordt afgehandeld door CanvasInteractionCatcher (NSEvent
    // .magnify), zodat het ook werkt als er iets geselecteerd is.

    @ViewBuilder
    private var boardShortcutButtons: some View {
        Group {
            Button("") { zoom(1.25) }.keyboardShortcut("+", modifiers: .command)
            Button("") { zoom(1.25) }.keyboardShortcut("=", modifiers: .command)
            Button("") { zoom(0.8) }.keyboardShortcut("-", modifiers: .command)
            Button("") { fit() }.keyboardShortcut("0", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func zoom(_ factor: CGFloat) {
        withAnimation(.spring(duration: 0.25)) { camera.zoomCentered(by: factor) }
    }

    private func fit() {
        withAnimation(.spring(duration: 0.3)) { camera.fitToContent(contentSize: boardSize, in: viewport) }
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
            backgroundMenuButton(isOpen: batchMenu == .background,
                                  toggle: { batchMenu = (batchMenu == .background) ? nil : .background },
                                  display: selectedPortraits.first)

            Divider().frame(height: 16).overlay(DSColor.Foreground.divider)

            // E29.3: Match lighting over de selectie (≥2). Normaliseert de
            // belichting van alle geselecteerde naar de eerste als referentie.
            // E32.1: gedeelde compacte pil (SF-Symbol-init) i.p.v. de inline-knop.
            if selection.count >= 2 {
                DSCapsuleToolButton(
                    Image(systemName: isMatchingLight ? "circle.dotted" : "sun.max"),
                    label: isMatchingLight ? "Matching…" : "Match lighting",
                    size: .compact,
                    action: { matchLightingSelection() }
                )
                .disabled(isMatchingLight)

                Divider().frame(height: 16).overlay(DSColor.Foreground.divider)
            }

            // Adjust: dezelfde kleurcorrectie op alle geselecteerde (dropdown).
            // E32.1: gedeelde compacte pil — active (menu open) = lime-ring.
            DSCapsuleToolButton(
                Image(systemName: "slider.horizontal.3"),
                label: "Adjust",
                isActive: batchMenu == .adjust,
                size: .compact,
                action: { batchMenu = (batchMenu == .adjust) ? nil : .adjust }
            )
            .overlay(alignment: .top) {
                if batchMenu == .adjust, let first = selectedPortraits.first,
                   let img = NSImage(data: first.cutoutData) {
                    EditColorPanel(
                        source: img,
                        initial: first.adjust,
                        onCommit: { _, after in applyAdjustToAll(after) }
                    )
                    .padding(DSMenuLayout.contentInset)
                    .frame(width: 360)
                    .fixedSize(horizontal: false, vertical: true)
                    .dsMenuSurface()
                    .offset(y: DSToolbarSize.compact.height
                              + DSToolbarSize.compact.containerPadding
                              + DSSpacing.gap2)
                    .zIndex(10)
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
                BackgroundPanel(portrait: display, onApply: { applyBackgroundToAll($0) })
                    .padding(DSMenuLayout.contentInset)
                    .frame(width: 320)
                    .fixedSize(horizontal: false, vertical: true)
                    .dsMenuSurface()
                    .offset(y: DSToolbarSize.compact.height
                              + DSToolbarSize.compact.containerPadding
                              + DSSpacing.gap2)
                    .zIndex(10)
            }
        }
    }

    /// E29.2/E31.7: pas dezelfde achtergrond toe op alle geselecteerde portretten.
    private func applyBackgroundToAll(_ background: PortraitBackground) {
        let targets = selectedPortraits
        let cache = thumbs
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Background")
        for p in targets {
            let before = p.background
            guard before != background else { continue }
            p.setBackground(background)
            cache.invalidate(p)
            ReversibleChange.register(
                undoManager, target: p,
                from: before, to: background, actionName: "Background"
            ) { portrait, bg in
                portrait.setBackground(bg)
                cache.invalidate(portrait)
            }
        }
        undoManager?.endUndoGrouping()
    }

    private func undoableSetBackground(_ background: PortraitBackground, on node: Portrait2) {
        let before = node.background
        guard before != background else { return }
        node.setBackground(background)
        thumbs.invalidate(node)
        let cache = thumbs
        ReversibleChange.register(
            undoManager, target: node,
            from: before, to: background, actionName: "Background"
        ) { portrait, bg in
            portrait.setBackground(bg)
            cache.invalidate(portrait)
        }
    }

    /// E29.2: pas dezelfde Adjust-laag toe op alle geselecteerde portretten.
    private func applyAdjustToAll(_ adjust: PortraitAdjust) {
        let targets = selectedPortraits
        let cache = thumbs
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Adjust")
        for p in targets {
            let before = p.adjust
            p.adjust = adjust
            p.touch()
            cache.invalidate(p)
            AdjustUndo.register(
                undoManager, target: p,
                apply: { [p, cache] adj in
                    p.adjust = adj
                    p.touch()
                    cache.invalidate(p)
                },
                undoTo: before, redoTo: adjust, actionName: "Adjust"
            )
        }
        undoManager?.endUndoGrouping()
    }

    /// E29.3: "Match lighting" over de selectie — trekt de belichting/kleurbalans
    /// van alle geselecteerde portretten naar de eerste als referentie (zelfde
    /// `SetLightingNormalizer` als E12.2, nu vanuit de board-multi-select). Eén
    /// undo-groep; de board-thumbnails worden geïnvalideerd zodat de nieuwe
    /// cutouts opnieuw decoderen.
    private func matchLightingSelection() {
        guard !isMatchingLight else { return }
        let targets = selectedPortraits
        guard targets.count >= 2, let reference = targets.first,
              let refCG = NSImage(data: reference.cutoutData)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil),
              let refStats = SetLightingNormalizer.referenceStats(of: refCG) else { return }
        isMatchingLight = true
        Task { @MainActor in
            defer { isMatchingLight = false }
            var items: [(Portrait2, Data, Data)] = []
            for p in targets where p.persistentModelID != reference.persistentModelID {
                guard let cg = NSImage(data: p.cutoutData)?
                        .cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let outCG = SetLightingNormalizer.match(cg, to: refStats),
                      let png = NSBitmapImageRep(cgImage: outCG).representation(using: .png, properties: [:])
                else { continue }
                items.append((p, p.cutoutData, png))
            }
            undoManager?.beginUndoGrouping()
            undoManager?.setActionName("Match Lighting")
            for (p, before, after) in items {
                p.cutoutData = after
                p.touch()
                CutoutDataUndo.register(undoManager, portrait: p, undoTo: before, redoTo: after, actionName: "Match Lighting")
                thumbs.invalidate(p)
            }
            undoManager?.endUndoGrouping()
        }
    }

    // MARK: - E30.1 in-place editen op één node

    /// E31.7: top-toolbar bij precies één selectie = dezelfde frame-lokale
    /// `CanvasActionToolbar` als de single-editor, getrimd tot board-relevante
    /// controls (Frame ▾ met Shape + Flip · Background-panel). Auto-frame/Grid
    /// (editor-only transform/overlay) zijn verborgen. Adjust zit nu onder
    /// "Enhance" in de bottom-capsule — net als de editor.
    private func singleEditTopBar(_ node: Portrait2) -> some View {
        CanvasActionToolbar(
            onFlip: { flipNode(node) },
            frameShape: node.frameShape,
            onSetFrameShape: { setNodeFrameShape($0, node) },
            activeMenu: $canvasMenu,
            gridEnabled: .constant(false),
            showFramingActions: false,
            showGrid: false,
            background: { BackgroundPanel(portrait: node, onApply: { undoableSetBackground($0, on: node) }) }
        )
    }

    /// E31.7: zet de frame-vorm van één board-node (zelfde als EditorView).
    private func setNodeFrameShape(_ shape: ExportShape, _ node: Portrait2) {
        withAnimation(.spring(duration: 0.3)) { node.frameShape = shape }
        node.touch()
    }

    /// E31.7: bottom-toolbar bij precies één selectie = dezelfde `DSBottomToolbar`-
    /// capsule als de single-editor, met de GEDEELDE items (Enhance · Effects ·
    /// Face · Hair · Clothing). Het actieve paneel zweeft als dropdown erboven.
    /// "Enhance" (.edit) opent het kleur/Adjust-paneel — Adjust verhuisde hierheen
    /// uit de oude top-bar.
    private func singleEditBottomBar(_ node: Portrait2) -> some View {
        VStack(spacing: DSSpacing.gap2) {
            // Actief paneel boven de balk.
            if let base = NSImage(data: node.cutoutData) {
                Group {
                    switch editTool {
                    case .edit:
                        DSEditPanel(title: "Enhance", maxWidth: 420) {
                            EditColorPanel(
                                source: base,
                                initial: node.adjust,
                                onCommit: { _, after in applyAdjustToAll(after) },
                                onRetouch: { retouchNode(node) },
                                showRetouch: true
                            )
                        }
                    case .effects:
                        EffectsPanel(baseImage: base, entitlement: entitlement, portrait: node,
                                     onApply: { undoableApplyToNodePreservingAlpha($0, node, actionName: "Apply effect") })
                            .id(node.persistentModelID)
                    case .clothing:
                        ClothesPanel(baseImage: base, entitlement: entitlement,
                                     onApply: { undoableApplyToNode($0, node, actionName: "Change clothing") })
                            .id(node.persistentModelID)
                    case .hair:
                        HairPanel(baseImage: base, entitlement: entitlement,
                                  onApply: { undoableApplyToNode($0, node, actionName: "Change hair") })
                            .id(node.persistentModelID)
                    case .face where AppFeatureFlags.faceEnabled:
                        DSEditPanel(
                            title: "Face",
                            credits: CreditMeter.chipLabel(for: .generativeStandard),
                            maxWidth: 420
                        ) {
                            FaceActionsPanel(
                                baseImage: base,
                                entitlement: entitlement,
                                onApply: { undoableApplyToNodePreservingAlpha($0, node, actionName: "Face edit") },
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
            }

            DSBottomToolbar(items: EditorView.visibleToolbarItems, selection: $editTool)
        }
    }

    /// E30.1: een cloud/flip-resultaat op de node toepassen via dezelfde pipeline
    /// als de editor (re-isolatie bij volle achtergrond) → cutoutData + thumbnail.
    private func applyToNode(_ image: NSImage, _ node: Portrait2) {
        model.select(node)
        model.applyEffectResult(image)
        thumbs.invalidate(node)
        editTool = nil
    }

    /// Effects/face-edits: bewaart de cutout-alpha als masker i.p.v. Vision
    /// opnieuw te draaien op een artistiek gestyled beeld.
    private func applyToNodePreservingAlpha(_ image: NSImage, _ node: Portrait2) {
        model.select(node)
        model.applyEffectResult(image, preserveSourceAlpha: true)
        thumbs.invalidate(node)
        editTool = nil
    }

    /// Zelfde als applyToNode maar registreert ook een undo/redo-entry zodat
    /// Cmd+Z de bewerking terugdraait en Cmd+Shift+Z 'm hertoepast.
    private func undoableApplyToNode(_ image: NSImage, _ node: Portrait2, actionName: String) {
        guard let before = NSImage(data: node.cutoutData) else {
            applyToNode(image, node)
            return
        }
        applyToNode(image, node)
        let cache = thumbs
        ImageEnhanceUndo.register(
            undoManager, target: node,
            apply: { [model, cache] img in
                model.select(node)
                model.applyEffectResult(img)
                cache.invalidate(node)
            },
            undoTo: before, redoTo: image, actionName: actionName
        )
    }

    private func undoableApplyToNodePreservingAlpha(_ image: NSImage, _ node: Portrait2, actionName: String) {
        guard let before = NSImage(data: node.cutoutData) else {
            applyToNodePreservingAlpha(image, node)
            return
        }
        applyToNodePreservingAlpha(image, node)
        let cache = thumbs
        ImageEnhanceUndo.register(
            undoManager, target: node,
            apply: { [model, cache] img in
                model.select(node)
                model.applyEffectResult(img, preserveSourceAlpha: true)
                cache.invalidate(node)
            },
            undoTo: before, redoTo: image, actionName: actionName
        )
    }

    /// Spiegelt de cutout van de node horizontaal (zelfde transform als editor).
    private func flipNode(_ node: Portrait2) {
        let base = NSImage(data: node.cutoutData) ?? NSImage()
        guard let cg = base.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }
        ctx.translateBy(x: CGFloat(cg.width), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let out = ctx.makeImage() else { return }
        undoableApplyToNode(NSImage(cgImage: out, size: base.size), node, actionName: "Flip")
    }

    /// One-click retouch op de node (lokaal, zelfde enhancer als de editor).
    private func retouchNode(_ node: Portrait2) {
        guard let cg = NSImage(data: node.cutoutData)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil),
              let out = PortraitEnhancer.magicRetouch(cg) else { return }
        undoableApplyToNode(NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height)), node, actionName: "One click retouch")
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
                Button("Fit", action: fit)
                    .buttonStyle(.plain)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .padding(.horizontal, DSSpacing.gap3)
                    .frame(height: 30)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
            }
            .padding(DSSpacing.gap4)
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
    let isSelected: Bool
    let frameShape: ExportShape
    let name: String
    let role: String
    let backgroundColorHex: String?
    let backgroundImageData: Data?
    /// Portrait-modus (achtergrond-blur) — vervaagt de custom-achtergrond op de board.
    let portraitBlur: Bool
    /// `Portrait2.updatedAt` — O(1) wijzigings-token voor de (dure) bg-image-`Data`:
    /// `setBackground` bumpt 'm, dus we hoeven nooit de bytes te vergelijken.
    let contentVersion: Date
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
                    .foregroundStyle(isSelected ? DSColor.Action.primary : DSColor.Foreground.primary)
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
            // E27.5: gecachete, verkleinde thumbnail (geen re-decode per frame),
            // E30.2 mét de niet-destructieve Adjust-laag erop (WYSIWYG). De cache is
            // (id, updatedAt)-gekeyd (E27.6 Tier 0), dus in-place-edits verversen vanzelf.
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
