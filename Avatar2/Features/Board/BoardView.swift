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

            ForEach(Array(portraits.enumerated()), id: \.element.persistentModelID) { index, portrait in
                let c = center(of: portrait, index: index)
                node(portrait)
                    .position(x: c.x, y: c.y)
            }
        }
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
            if let image = NSImage(data: portrait.cutoutData) {
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
