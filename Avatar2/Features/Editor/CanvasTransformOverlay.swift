// Screen-space transform-overlay (E27.3) — de selectie-handles + het kader +
// de ESC-deselect. Bewust BUITEN de camera-transform (E27.1) én buiten de
// canvas-clip getekend, zodat ze (a) op élk zoomniveau dezelfde grootte op het
// scherm houden (niet onleesbaar/onbruikbaar) en (b) bij een groot-geschaald
// onderwerp zichtbaar/grijpbaar worden door uit te zoomen — de camera trekt de
// hoeken dan het beeld weer in. De handles staan in EditorView als overlay op
// de (camera-getransformeerde) DSCanvasCard; posities worden uit de onderwerp-
// transform + de camera berekend.
//
// De positionerings- en scale-math is 1-op-1 die van EditorCanvasView (E24.8) —
// dezelfde FramingConstants, dezelfde clamp, dezelfde TransformUndo. De drag-
// ratio is invariant onder camera-zoom (beide afstanden schalen gelijk mee).

import AppKit
import AvatarUI
import SwiftUI

struct CanvasTransformOverlay: View {
    /// Zijde van de (niet-gezoomde) canvas-vierkant-slot, in punten.
    let side: CGFloat
    /// Midden van de kaart in viewport-coördinaten (default: vierkant gecentreerd).
    var cardCenter: CGPoint?
    let image: NSImage
    let portrait: Portrait2
    /// De huidige camera (E27.1) — mapt canvas-punten naar het scherm.
    let camera: CanvasCamera
    /// Pan-drag bezig → handles even verbergen (minder druk), zoals E24.29.
    let isPanning: Bool
    @Binding var isSelected: Bool
    let undoManager: UndoManager?

    @State private var handleStartScale: Double?
    @State private var handleStartDist: CGFloat = 0
    @State private var handleBefore: TransformUndo.Snapshot?

    private static let space = "canvasTransformOverlay"

    var body: some View {
        let t = resolvedTransform()
        let factor = side / FramingConstants.editCanvas.width
        // Onderwerp-box in canvas-punten (vóór camera).
        let imgW = image.size.width * t.scale * factor
        let imgH = image.size.height * t.scale * factor
        let centerCanvas = CGPoint(
            x: (t.offsetX + image.size.width * t.scale / 2) * factor,
            y: (t.offsetY + image.size.height * t.scale / 2) * factor
        )
        // Camera-mapping: scherm = midden + scale·(p − midden) + offset.
        let vp = cardCenter ?? CGPoint(x: side / 2, y: side / 2)
        let center = CGPoint(
            x: vp.x + camera.scale * (centerCanvas.x - vp.x) + camera.offset.width,
            y: vp.y + camera.scale * (centerCanvas.y - vp.y) + camera.offset.height
        )
        let halfW = imgW / 2 * camera.scale
        let halfH = imgH / 2 * camera.scale
        let corners = [
            CGPoint(x: center.x - halfW, y: center.y - halfH),
            CGPoint(x: center.x + halfW, y: center.y - halfH),
            CGPoint(x: center.x - halfW, y: center.y + halfH),
            CGPoint(x: center.x + halfW, y: center.y + halfH),
        ]

        ZStack {
            // E24.29: selectiekader op de onderwerp-box (vaste 1pt lijn —
            // screen-space). primaryForeground i.p.v. lime-fill: leesbaar op lichte
            // én donkere canvas (E23 theme-bewust).
            Rectangle()
                .strokeBorder(DSColor.Action.primaryForeground.opacity(0.85), lineWidth: 1)
                .frame(width: max(0, halfW * 2), height: max(0, halfH * 2))
                .position(center)
                .allowsHitTesting(false)

            ForEach(0..<corners.count, id: \.self) { i in
                handleDot(at: corners[i], center: center)
            }

            // E24.32: ESC deselecteert altijd (window-brede cancelAction op een
            // verborgen knop) — staat los van de gesture-state.
            Button("") { isSelected = false }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: side, height: side)
        // Tijdens pannen even weg (zoals E24.29 deed met isDragging).
        .opacity(isPanning ? 0 : 1)
        .dsMotion(DSMotion.micro, value: isPanning)
        .coordinateSpace(name: Self.space)
    }

    private func handleDot(at pos: CGPoint, center: CGPoint) -> some View {
        // E24.29: 10pt-dot — vaste schermgrootte (screen-space overlay).
        Circle()
            .fill(DSColor.Background.card)
            .overlay(Circle().strokeBorder(DSColor.Action.primaryForeground, lineWidth: 1.5))
            .dsShadow(.handle)
            .frame(width: 10, height: 10)
            .position(pos)
            .gesture(
                DragGesture(coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        if handleStartScale == nil {
                            handleStartScale = resolvedTransform().scale
                            handleStartDist = max(1, distance(value.startLocation, center))
                            handleBefore = TransformUndo.snapshot(of: portrait)
                        }
                        guard let startScale = handleStartScale else { return }
                        // De afstand-verhouding bepaalt de nieuwe onderwerp-schaal;
                        // de camera-zoom schaalt beide afstanden gelijk mee en valt
                        // zo uit de verhouding.
                        let ratio = distance(value.location, center) / handleStartDist
                        applySubjectScale(to: startScale * ratio)
                    }
                    .onEnded { _ in
                        // Eén touch + één undo-stap per afgeronde drag.
                        portrait.touch()
                        registerUndo()
                        handleStartScale = nil
                        handleBefore = nil
                    }
            )
    }

    // MARK: - Onderwerp-transform (1-op-1 met EditorCanvasView — zelfde constants)

    private func resolvedTransform() -> (offsetX: Double, offsetY: Double, scale: Double) {
        if portrait.scale > 0 { return (portrait.offsetX, portrait.offsetY, portrait.scale) }
        return fitTransform()
    }

    private func fitTransform() -> (offsetX: Double, offsetY: Double, scale: Double) {
        // Canonieke padded-fit: AutoFramer.fitTransform (gedeeld met
        // EditorCanvasView — voorheen hier 1-op-1 gedupliceerd).
        let t = AutoFramer.fitTransform(cutoutSize: image.size)
        return (t.offset.width, t.offset.height, t.scale)
    }

    /// Schaalt het onderwerp om zijn eigen midden, geclampt aan de fit-band.
    private func applySubjectScale(to newScale: Double) {
        let cur = resolvedTransform()
        let baseline = fitTransform().scale
        let clamped = min(
            baseline * FramingConstants.maxZoomFactor,
            max(baseline * FramingConstants.minZoomFactor, newScale)
        )
        guard clamped != cur.scale else { return }
        let cxU = cur.offsetX + image.size.width * cur.scale / 2
        let cyU = cur.offsetY + image.size.height * cur.scale / 2
        portrait.offsetX = cxU - image.size.width * clamped / 2
        portrait.offsetY = cyU - image.size.height * clamped / 2
        portrait.scale = clamped
    }

    private func registerUndo() {
        guard let handleBefore else { return }
        TransformUndo.register(
            undoManager,
            portrait: portrait,
            undoTo: handleBefore,
            redoTo: TransformUndo.snapshot(of: portrait),
            actionName: "Scale"
        )
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
