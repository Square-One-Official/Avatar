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
import AvatarUI
import SwiftData
import SwiftUI

struct BoardView: View {
    /// Dezelfde bron als de sidebar (E05.4): alle portretten, jongste eerst.
    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
    /// Klik op een node → openen (selecteren) in de editor.
    let onOpen: (Portrait2) -> Void

    @Environment(\.undoManager) private var undoManager

    /// E27.5: gedecodeerde + verkleinde thumbnails, één keer per portret-id
    /// gedecodeerd (geen re-decode bij elke pan/zoom-frame). Referentietype zodat
    /// het over body-evaluaties heen blijft leven.
    @State private var thumbs = BoardThumbnailCache()

    // Camera met een lagere min-zoom dan de editor, zodat een grote set in beeld past.
    @State private var camera = CanvasCamera(minScale: 0.1)
    @State private var lastMagnification: CGFloat = 1
    @State private var viewport: CGSize = .zero
    /// De laatst auto-gefitte camera. Zolang de camera hieraan gelijk is (de
    /// gebruiker heeft 'm niet aangeraakt) blijft de board mee-fitten op
    /// viewport-/set-wijzigingen; zodra de gebruiker pant/zoomt (camera ≠ deze)
    /// stopt het auto-fitten.
    @State private var lastFit: CanvasCamera?

    // Drag-state (board-space).
    @State private var dragStart: CGPoint?

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
                        .simultaneousGesture(pinch)
                }

                hud
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { viewport = geo.size; assignInitialLayout(); fitIfNeeded() }
            .onChange(of: geo.size) { _, s in viewport = s; fitIfNeeded() }
            // @Query laadt ná de eerste render → layout + fit zodra de set binnen
            // is; `didInitialFit` latcht pas bij een niet-lege set.
            .onChange(of: portraits.count) { _, _ in assignInitialLayout(); fitIfNeeded() }
        }
    }

    // MARK: - Board-canvas (absolute node-posities)

    private var boardCanvas: some View {
        ZStack(alignment: .topLeading) {
            // Onzichtbaar vlak dat de board-maat bepaalt (de nodes positioneren
            // hierop absoluut; lege ruimte = geen hit → camera-pan blijft werken).
            Color.clear

            // E27.5: virtualisatie — alleen nodes die in (of net buiten) de
            // zichtbare viewport vallen, renderen. Scheelt views + werk bij pan/
            // zoom op een grote set.
            ForEach(visibleNodes(), id: \.portrait.persistentModelID) { item in
                node(item.portrait)
                    .position(x: item.center.x, y: item.center.y)
            }
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
        VStack(spacing: labelGap) {
            cardSurface(portrait)
                .frame(width: cardSide, height: cardSide)
            VStack(spacing: 2) {
                Text(portrait.name.isEmpty ? "Untitled" : portrait.name)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
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
        // Klik (kleine beweging) opent; grotere beweging = node verslepen.
        .onTapGesture { onOpen(portrait) }
        .gesture(dragGesture(for: portrait))
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
            // E27.5: gecachete, verkleinde thumbnail (geen re-decode per frame).
            if let image = thumbs.thumbnail(for: portrait, maxDimension: cardSide * 2) {
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

    /// Eenmalig: nog niet-geplaatste nodes krijgen hun auto-grid-positie
    /// persistent (zodat ze daarna sleepbaar/stabiel zijn). Wijzigt geen
    /// `updatedAt` (board-layout ≠ "bewerkt").
    private func assignInitialLayout() {
        for (index, portrait) in portraits.enumerated() where !portrait.boardPlaced {
            let c = autoCenter(order: index)
            portrait.boardX = c.x
            portrait.boardY = c.y
            portrait.boardOrder = index
            portrait.boardPlaced = true
        }
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
        DragGesture(minimumDistance: 5)
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

    private var pinch: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / max(0.0001, lastMagnification)
                lastMagnification = value
                camera.zoomCentered(by: delta)
            }
            .onEnded { _ in lastMagnification = 1 }
    }

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

    private var hud: some View {
        VStack {
            Spacer()
            HStack {
                Text("\(portraits.count) portraits — drag to arrange, click to edit")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.muted)
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
    private(set) var decodeCount = 0

    func thumbnail(for portrait: Portrait2, maxDimension: CGFloat) -> NSImage? {
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
    static func register(_ undoManager: UndoManager?, portrait: Portrait2, from old: CGPoint, to new: CGPoint) {
        guard let undoManager, old != new else { return }
        undoManager.registerUndo(withTarget: portrait) { target in
            let current = CGPoint(x: target.boardX, y: target.boardY)
            target.boardX = old.x
            target.boardY = old.y
            register(undoManager, portrait: target, from: current, to: old)
        }
        undoManager.setActionName("Move portrait")
    }
}
