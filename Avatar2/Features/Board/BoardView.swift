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

    // E30.1: actief bottom-tool/dropdown bij ÉÉN geselecteerde node (in-place
    // editen op de board, zelfde panelen als de editor).
    @State private var editTool: EditTool?
    private enum EditTool: Hashable { case background, adjust, effects, face, clothing, hair }

    /// De enige geselecteerde node (nil bij 0 of ≥2) — de in-place-edit-target.
    private var selectedNode: Portrait2? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return portraits.first { $0.persistentModelID == id }
    }

    /// E27.5: gedecodeerde + verkleinde thumbnails, één keer per portret-id
    /// gedecodeerd (geen re-decode bij elke pan/zoom-frame). Referentietype zodat
    /// het over body-evaluaties heen blijft leven.
    @State private var thumbs = BoardThumbnailCache()

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

    // E29.2: batch-toolbar (open dropdown) + de geselecteerde portretten.
    @State private var batchMenu: BatchMenu?
    // E29.3: loopt tijdens de "Match lighting"-normalisatie over de selectie.
    @State private var isMatchingLight = false
    private enum BatchMenu: Hashable { case background, adjust }

    /// E29.2: batch-achtergrond-presets (Transparent + een paar kleuren).
    private static let batchBackgrounds: [String?] =
        [nil, "FFFFFF", "111111", "D5F466", "8B5CF6", "F472B6", "38BDF8"]

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
                            CanvasInteractionCatcher(camera: $camera)
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
            .onAppear { viewport = geo.size; assignInitialLayout(); fitIfNeeded(); debugSeedSelection() }
            .onChange(of: geo.size) { _, s in viewport = s; fitIfNeeded() }
            // @Query laadt ná de eerste render → layout + fit zodra de set binnen
            // is; `didInitialFit` latcht pas bij een niet-lege set.
            .onChange(of: portraits.count) { _, _ in assignInitialLayout(); fitIfNeeded() }
            // E30.1: één-selectie → richt de gedeelde edit-pipeline op die node;
            // bij 0 of ≥2 sluit het bottom-tool-paneel.
            .onChange(of: selection) { _, sel in
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
                node(item.portrait)
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
    /// toevoegen aan de bestaande selectie).
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                marquee = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
            }
            .onEnded { _ in
                guard let rect = marquee else { return }
                let hits = Set(
                    portraits.enumerated()
                        .filter { rect.contains(center(of: $1, index: $0)) }
                        .map { $1.persistentModelID }
                )
                let additive = NSEvent.modifierFlags.contains(.command)
                    || NSEvent.modifierFlags.contains(.shift)
                selection = additive ? selection.union(hits) : hits
                marquee = nil
            }
    }

    /// E27.5: de nodes waarvan het midden binnen de (met een cel-marge verruimde)
    /// zichtbare board-rect valt. Vóór de eerste layout (viewport 0) → alles.
    private func visibleNodes() -> [(portrait: Portrait2, center: CGPoint)] {
        let all = portraits.enumerated().map { (portrait: $1, center: center(of: $1, index: $0)) }
        guard viewport.width > 0, viewport.height > 0, camera.scale > 0 else { return all }
        let rect = visibleBoardRect().insetBy(dx: -(cardSide + gap), dy: -(cellHeight + gap))
        return all.filter { rect.contains($0.center) }
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

    private func node(_ portrait: Portrait2) -> some View {
        let isSelected = selection.contains(portrait.persistentModelID)
        return VStack(spacing: labelGap) {
            cardSurface(portrait)
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
                Text(portrait.name.isEmpty ? "Untitled" : portrait.name)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(isSelected ? DSColor.Action.primary : DSColor.Foreground.primary)
                    .lineLimit(1)
                if !portrait.role.isEmpty {
                    Text(portrait.role)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .lineLimit(1)
                }
            }
            .frame(height: labelHeight)
        }
        .frame(width: cardSide, height: cellHeight)
        .contentShape(Rectangle())
        .dsHoverHighlight(cornerRadius: DSRadius.xl4)
        // E29.1: dubbelklik = openen in de editor; enkelklik = selecteren
        // (cmd/shift = toevoegen/afhalen). Sleep = node verplaatsen (E27.4).
        .onTapGesture(count: 2) { onOpen(portrait) }
        .onTapGesture { tapNode(portrait) }
        .gesture(dragGesture(for: portrait))
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

    /// Kaart-surface met het cutout-beeld, geclipt tot de frame-vorm (mini-
    /// DSCanvasCard, zonder de transform-machinerie).
    @ViewBuilder
    private func cardSurface(_ portrait: Portrait2) -> some View {
        let clip: AnyShape = portrait.frameShape == .circle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: DSRadius.xl4))
        ZStack {
            DSColor.Background.card
            // E29.2: de gekozen achtergrondkleur achter de cutout → batch-
            // Background is meteen zichtbaar op de board (WYSIWYG voor kleur).
            if let hex = portrait.backgroundColorHex, let c = Color(hexRGB: hex) {
                c
            }
            // E27.5: gecachete, verkleinde thumbnail (geen re-decode per frame),
            // E30.2 mét de niet-destructieve Adjust-laag erop (WYSIWYG).
            // E30.1: de node die je nú in-place bewerkt decodeert VERS (cache
            // omzeild) zodat een Effect/Flip/Hair-edit meteen op de node verschijnt
            // — applyEffectResult re-isoleert async, dus een cache-snapshot zou
            // achterlopen. Eén verse decode per render voor die ene node is prima.
            if let image = (portrait.persistentModelID == selection.first && selection.count == 1)
                ? thumbs.freshThumbnail(for: portrait, maxDimension: cardSide * 2)
                : thumbs.thumbnail(for: portrait, maxDimension: cardSide * 2) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(cardSide * 0.08)
            }
        }
        .clipShape(clip)
        .overlay(clip.stroke(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
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
    private func debugSeedSelection() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--board-select"), args.indices.contains(i + 1),
              let n = Int(args[i + 1]) else { return }
        selection = Set(portraits.prefix(n).map { $0.persistentModelID })
        // E29.2 smoke: pas een batch-achtergrond toe op de selectie ("none" = wissen).
        if let j = args.firstIndex(of: "--board-batch-bg"), args.indices.contains(j + 1) {
            let v = args[j + 1]
            applyBackgroundToAll(v == "none" ? nil : v)
        }
        // E29.3 smoke: match lighting over de selectie.
        if args.contains("--board-match-light") { matchLightingSelection() }
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

            Divider().frame(height: 16).overlay(DSColor.Foreground.divider)

            // Background: Transparent + presets, toegepast op alle geselecteerde.
            Text("Background")
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.muted)
            ForEach(Self.batchBackgrounds.indices, id: \.self) { i in
                backgroundSwatch(Self.batchBackgrounds[i])
            }

            Divider().frame(height: 16).overlay(DSColor.Foreground.divider)

            // E29.3: Match lighting over de selectie (≥2). Normaliseert de
            // belichting van alle geselecteerde naar de eerste als referentie.
            if selection.count >= 2 {
                Button { matchLightingSelection() } label: {
                    HStack(spacing: DSSpacing.gap1) {
                        Image(systemName: isMatchingLight ? "circle.dotted" : "sun.max")
                            .font(.system(size: 12))
                        Text(isMatchingLight ? "Matching…" : "Match lighting").dsTextStyle(.labelSmall)
                    }
                    .foregroundStyle(DSColor.Foreground.primary)
                    .padding(.horizontal, DSSpacing.gap2)
                    .frame(height: 28)
                    .dsHoverHighlight(cornerRadius: 14)
                }
                .buttonStyle(.plain)
                .disabled(isMatchingLight)

                Divider().frame(height: 16).overlay(DSColor.Foreground.divider)
            }

            // Adjust: dezelfde kleurcorrectie op alle geselecteerde (dropdown).
            Button { batchMenu = (batchMenu == .adjust) ? nil : .adjust } label: {
                HStack(spacing: DSSpacing.gap1) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 12))
                    Text("Adjust").dsTextStyle(.labelSmall)
                }
                .foregroundStyle(DSColor.Foreground.primary)
                .padding(.horizontal, DSSpacing.gap2)
                .frame(height: 28)
                .background(batchMenu == .adjust ? DSColor.Background.neutralStronger : .clear, in: Capsule())
                .dsHoverHighlight(cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                if batchMenu == .adjust, let first = selectedPortraits.first,
                   let img = NSImage(data: first.cutoutData) {
                    EditColorPanel(
                        source: img,
                        initial: first.adjust,
                        onCommit: { _, after in applyAdjustToAll(after); batchMenu = nil }
                    )
                    .padding(DSSpacing.gap4)
                    .frame(width: 360)
                    .fixedSize(horizontal: false, vertical: true)
                    .dsPanelSurface(cornerRadius: DSRadius.xl)
                    .offset(y: 40)
                    .zIndex(10)
                }
            }
        }
        .padding(.horizontal, DSSpacing.gap3)
        .padding(.vertical, DSSpacing.gap1)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
    }

    private func backgroundSwatch(_ hex: String?) -> some View {
        Button { applyBackgroundToAll(hex) } label: {
            ZStack {
                if let hex, let c = Color(hexRGB: hex) {
                    Circle().fill(c)
                } else {
                    // Transparent = dot-grid-achtige indicatie.
                    Circle().fill(DSColor.Background.neutralStronger)
                    Image(systemName: "circle.dotted").font(.system(size: 12))
                        .foregroundStyle(DSColor.Foreground.muted)
                }
            }
            .frame(width: 20, height: 20)
            .overlay(Circle().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
        }
        .buttonStyle(.plain)
        .help(hex == nil ? "Transparent" : "#\(hex!)")
    }

    /// E29.2: pas dezelfde achtergrond toe op alle geselecteerde portretten.
    private func applyBackgroundToAll(_ hex: String?) {
        for p in selectedPortraits {
            p.setBackground(hex.map(PortraitBackground.color) ?? .transparent)
        }
    }

    /// E29.2: pas dezelfde Adjust-laag toe op alle geselecteerde portretten.
    private func applyAdjustToAll(_ adjust: PortraitAdjust) {
        for p in selectedPortraits {
            p.adjust = adjust
            p.touch()
        }
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

    /// Top-toolbar bij precies één selectie: de normale editor-acties op de node
    /// (Background-presets · Adjust · Flip) — géén batch-framing/Match lighting.
    private func singleEditTopBar(_ node: Portrait2) -> some View {
        HStack(spacing: DSSpacing.gap2) {
            Text(node.name.isEmpty ? "Untitled" : node.name)
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.primary)
                .lineLimit(1)

            Divider().frame(height: 16).overlay(DSColor.Foreground.divider)

            // Background: dezelfde presets als batch (toegepast op deze ene node;
            // applyBackgroundToAll werkt op `selectedPortraits` = [node]).
            Text("Background")
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.muted)
            ForEach(Self.batchBackgrounds.indices, id: \.self) { i in
                backgroundSwatch(Self.batchBackgrounds[i])
            }

            Divider().frame(height: 16).overlay(DSColor.Foreground.divider)

            // Flip — spiegelt de cutout (zichtbaar op de node).
            Button { flipNode(node) } label: {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 12))
                    .foregroundStyle(DSColor.Foreground.primary)
                    .frame(width: 28, height: 28)
                    .dsHoverHighlight(cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .help("Flip horizontally")

            // Adjust — dezelfde kleurcorrectie als batch (op deze node).
            Button { editTool = (editTool == .adjust) ? nil : .adjust } label: {
                HStack(spacing: DSSpacing.gap1) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 12))
                    Text("Adjust").dsTextStyle(.labelSmall)
                }
                .foregroundStyle(DSColor.Foreground.primary)
                .padding(.horizontal, DSSpacing.gap2)
                .frame(height: 28)
                .background(editTool == .adjust ? DSColor.Background.neutralStronger : .clear, in: Capsule())
                .dsHoverHighlight(cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                if editTool == .adjust, let img = NSImage(data: node.cutoutData) {
                    EditColorPanel(
                        source: img,
                        initial: node.adjust,
                        onCommit: { _, after in applyAdjustToAll(after); editTool = nil }
                    )
                    .padding(DSSpacing.gap4)
                    .frame(width: 360)
                    .fixedSize(horizontal: false, vertical: true)
                    .dsPanelSurface(cornerRadius: DSRadius.xl)
                    .offset(y: 40)
                    .zIndex(10)
                }
            }
        }
        .padding(.horizontal, DSSpacing.gap3)
        .padding(.vertical, DSSpacing.gap1)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
    }

    /// Bottom-toolbar bij precies één selectie: de cloud-edit-tools van de editor
    /// (Effects/Face/Clothing/Hair), met het paneel als zwevende dropdown erboven.
    private func singleEditBottomBar(_ node: Portrait2) -> some View {
        VStack(spacing: DSSpacing.gap2) {
            // Actief paneel boven de balk.
            if let base = NSImage(data: node.cutoutData) {
                Group {
                    switch editTool {
                    case .effects:
                        EffectsPanel(baseImage: base, entitlement: entitlement, portrait: node,
                                     onApply: { applyToNode($0, node) })
                            .id(node.persistentModelID)
                    case .clothing:
                        ClothesPanel(baseImage: base, entitlement: entitlement,
                                     onApply: { applyToNode($0, node) })
                            .id(node.persistentModelID)
                    case .hair:
                        HairPanel(baseImage: base, entitlement: entitlement,
                                  onApply: { applyToNode($0, node) })
                            .id(node.persistentModelID)
                    case .face:
                        FaceActionsPanel(
                            onRetouch: { retouchNode(node) },
                            onProFeature: { _ = entitlement.allowCloudFeature() },
                            isPro: entitlement.isProActive,
                            activeToggles: []
                        )
                    default:
                        EmptyView()
                    }
                }
                .frame(width: 420)
                .fixedSize(horizontal: false, vertical: true)
                .dsPanelSurface(cornerRadius: DSRadius.xl)
            }

            HStack(spacing: DSSpacing.gap1) {
                bottomToolButton("Effects", "wand.and.stars", .effects)
                bottomToolButton("Face", "face.smiling", .face)
                bottomToolButton("Clothing", "tshirt", .clothing)
                bottomToolButton("Hair", "comb", .hair)
            }
            .padding(.horizontal, DSSpacing.gap2)
            .padding(.vertical, DSSpacing.gap1)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
        }
    }

    private func bottomToolButton(_ label: String, _ icon: String, _ tool: EditTool) -> some View {
        Button { editTool = (editTool == tool) ? nil : tool } label: {
            HStack(spacing: DSSpacing.gap1) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).dsTextStyle(.labelSmall)
            }
            .foregroundStyle(DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap3)
            .frame(height: 30)
            .background(editTool == tool ? DSColor.Background.neutralStronger : .clear, in: Capsule())
            .dsHoverHighlight(cornerRadius: 15)
        }
        .buttonStyle(.plain)
    }

    /// E30.1: een cloud/flip-resultaat op de node toepassen via dezelfde pipeline
    /// als de editor (re-isolatie bij volle achtergrond) → cutoutData + thumbnail.
    private func applyToNode(_ image: NSImage, _ node: Portrait2) {
        model.select(node)
        model.applyEffectResult(image)
        thumbs.invalidate(node)
        editTool = nil
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
        applyToNode(NSImage(cgImage: out, size: base.size), node)
    }

    /// One-click retouch op de node (lokaal, zelfde enhancer als de editor).
    private func retouchNode(_ node: Portrait2) {
        guard let cg = NSImage(data: node.cutoutData)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil),
              let out = PortraitEnhancer.magicRetouch(cg) else { return }
        applyToNode(NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height)), node)
    }

    private var hud: some View {
        VStack {
            Spacer()
            HStack {
                Text(selection.isEmpty
                     ? "\(portraits.count) portraits — click to select, double-click to edit"
                     : "\(selection.count) selected")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(selection.isEmpty ? DSColor.Foreground.muted : DSColor.Foreground.primary)
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

/// E27.5: thumbnail-cache voor de board — decodeert + verkleint elke cutout één
/// keer (per portret-id) en bewaart het resultaat, zodat pan/zoom geen volledige
/// re-decode + draw van de bron-pixels meer triggert. `decodeCount` is een
/// meet-haak (voor/na in de Result).
@MainActor
final class BoardThumbnailCache {
    private var cache: [PersistentIdentifier: NSImage] = [:]
    /// E30.2: de adjusted thumbnail, gecachet per (id, adjust-stand) — zodat de
    /// niet-destructieve Adjust-laag ook op de board-node zichtbaar is (WYSIWYG)
    /// zonder elke frame te her-renderen.
    private var adjustedCache: [PersistentIdentifier: (adjust: PortraitAdjust, image: NSImage)] = [:]
    private(set) var decodeCount = 0

    /// Gecachete, verkleinde thumbnail MÉT de Adjust-laag (voor niet-bewerkte nodes).
    func thumbnail(for portrait: Portrait2, maxDimension: CGFloat) -> NSImage? {
        guard let raw = rawThumbnail(for: portrait, maxDimension: maxDimension) else { return nil }
        return adjusted(raw, portrait: portrait)
    }

    /// E30.2: verse (ongecachete) adjusted thumbnail — voor de node die je nú
    /// in-place bewerkt: cutoutData verandert async (re-isolatie), dus altijd
    /// opnieuw decoderen i.p.v. een snapshot.
    func freshThumbnail(for portrait: Portrait2, maxDimension: CGFloat) -> NSImage? {
        guard let full = NSImage(data: portrait.cutoutData) else { return nil }
        let thumb = Self.downscaled(full, maxDimension: maxDimension)
        return portrait.adjust.isNeutral ? thumb : (Self.applyAdjust(thumb, portrait.adjust) ?? thumb)
    }

    /// De rauwe (ongeadjustede) downscaled thumbnail, één keer per id gedecodeerd.
    private func rawThumbnail(for portrait: Portrait2, maxDimension: CGFloat) -> NSImage? {
        let id = portrait.persistentModelID
        if let cached = cache[id] { return cached }
        guard let full = NSImage(data: portrait.cutoutData) else { return nil }
        let thumb = Self.downscaled(full, maxDimension: maxDimension)
        cache[id] = thumb
        decodeCount += 1
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--board-perf") {
            NSLog("BOARD thumb decode #\(decodeCount) id=\(id)")
        }
        #endif
        return thumb
    }

    /// Pas de Adjust-laag toe op een rauwe thumbnail, gecachet per adjust-stand.
    /// Neutraal → de rauwe thumb ongewijzigd (geen render).
    private func adjusted(_ raw: NSImage, portrait: Portrait2) -> NSImage {
        let adjust = portrait.adjust
        guard !adjust.isNeutral else { return raw }
        let id = portrait.persistentModelID
        if let cached = adjustedCache[id], cached.adjust == adjust { return cached.image }
        let out = Self.applyAdjust(raw, adjust) ?? raw
        adjustedCache[id] = (adjust, out)
        return out
    }

    private static func applyAdjust(_ image: NSImage, _ adjust: PortraitAdjust) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let out = PortraitEnhancer.colorAdjust(
                cg, brightness: adjust.brightness, contrast: adjust.contrast,
                saturation: adjust.saturation, temperatureShift: adjust.temperature
              ) else { return nil }
        return NSImage(cgImage: out, size: image.size)
    }

    /// E29.3: vergeet de cache voor één portret (na een cutout-wijziging zoals
    /// Match lighting) → de board decodeert de nieuwe cutout opnieuw.
    func invalidate(_ portrait: Portrait2) {
        cache[portrait.persistentModelID] = nil
        adjustedCache[portrait.persistentModelID] = nil
    }

    /// Teken de bron in een kleiner NSImage (aspect behouden); ≥ bronmaat → bron.
    private static func downscaled(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let factor = min(1, maxDimension / max(size.width, size.height))
        guard factor < 1 else { return image }
        let target = NSSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())
        let out = NSImage(size: target)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: size),
            operation: .copy, fraction: 1
        )
        out.unlockFocus()
        return out
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
