// Canvas-transform (E06.4) — pan/zoom/snap van het cutout binnen de vaste
// 1:1-kaart. Mechanics 1-op-1 geport uit v1 EditorView (drag/snap/haptics,
// regels ~252–350): 1024-units canvasruimte, shift = dominante as,
// snap-hysterese enter 12 / exit 24 met .alignment-tick, .generic-tick per
// 24 units (continue dragtextuur), zoom 0,5×–3× om het canvasmidden.
// Dubbelklik = reset naar fill-fit; E06.5 vervangt dat door echt
// auto-frame. Y-snap = canvasmidden zoals v1 — de ooglijn-snap verhuist
// naar E06.5 zodra eyeCenter (ProcessedSubject) op het portret bekend is;
// de guide toont de standaard-ooglijn al wél.
//
// Transform persisteert per portret (Portrait2.offsetX/offsetY/scale,
// scale 0 = nog geen transform → berekende fill-fit), met touch() zodat
// "laatst bewerkt" (punt 13) klopt.

import AppKit
import AvatarUI
import SwiftUI

struct EditorCanvasView: View {
    let image: NSImage
    let portrait: Portrait2?
    /// E24.26: grid/thirds-overlay aan/uit (toolbar-toggle). De gids verschijnt
    /// alléén als dit aan staat én er actief geselecteerd/getransformeerd wordt.
    var gridEnabled: Bool = false
    // E24.17: onderwerp geselecteerd → transform-handles zichtbaar (klik op de
    // afbeelding selecteert, klik erbuiten deselecteert). E24.29: binding zodat
    // EditorView het dot-grid kan dimmen tijdens transform.
    @Binding var isSelected: Bool
    /// E27.3: pan-drag bezig → EditorView dimt de (screen-space) handles weg.
    @Binding var isPanning: Bool
    /// E24.16/24.8: de frame-vorm clipt het BEELD (niet de handles), zodat de
    /// selectie-handles bij een cirkel-frame zichtbaar/bruikbaar blijven.
    var frameShape: ExportShape = .square
    /// E27.3: de huidige camera-VIEW-zoom (E27.1). De handles + uitlijn-gids
    /// zitten ín de scène en schalen dus mee met de camera; we delen hun
    /// pixel-maten (dot/lijn-dikte) door deze factor zodat ze op élk zoomniveau
    /// dezelfde grootte op het scherm houden (niet onleesbaar/onbruikbaar) —
    /// visueel gelijk aan een screen-space-overlay, mét behoud van de
    /// 24.8/24.32-positionerings- en drag-logica. Posities (op het onderwerp)
    /// schalen wél mee, zodat ze op de hoeken blijven plakken.
    var cameraScale: CGFloat = 1

    @State private var dragStart: CGSize?
    @State private var isDragging = false
    @State private var snappedX = false
    @State private var snappedY = false
    @State private var lastHapticTickX: Double = 0
    @State private var lastHapticTickY: Double = 0
    // E24.19 smoke-haak: forceer de (vaste) uitlijn-gids zichtbaar.
    @State private var debugShowGuide = false

    // E06.2: before-snapshots zodat een afgerond gebaar één undo-stap is.
    @State private var dragBefore: TransformUndo.Snapshot?
    @Environment(\.undoManager) private var undoManager

    /// In-memory transform voor het (theoretische) geval zonder model —
    /// het canvas werkt dan gewoon, alleen zonder persistentie.
    @State private var localTransform = CanvasTransform(offsetX: 0, offsetY: 0, scale: 0)

    private let haptics = NSHapticFeedbackManager.defaultPerformer

    /// E27.3: tegen-schaal voor handles/gids zodat hun pixel-maten constant op
    /// het scherm blijven onder de camera-zoom (de scène scaleEffect't ×camera,
    /// dus we tekenen ×1/camera).
    private var inverseCameraScale: CGFloat { 1 / max(0.0001, cameraScale) }

    // v1-constanten (EditorView ~57/78/79).
    private let hapticStep: Double = 24
    private let snapEnter: Double = 12
    private let snapExit: Double = 24

    struct CanvasTransform {
        var offsetX: Double
        var offsetY: Double
        var scale: Double
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let transform = resolvedTransform()
            let factor = side / FramingConstants.editCanvas.width
            let imgW = image.size.width * transform.scale * factor
            let imgH = image.size.height * transform.scale * factor
            let imgCenter = CGPoint(
                x: (transform.offsetX + image.size.width * transform.scale / 2) * factor,
                y: (transform.offsetY + image.size.height * transform.scale / 2) * factor
            )

            let clip: AnyShape = frameShape == .circle ? AnyShape(Circle()) : AnyShape(Rectangle())
            ZStack {
                // E24.17: klik BUITEN het onderwerp (de hoeken bij een cirkel,
                // of de marge) = onderwerp deselecteren → handles weg.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isSelected = false }

                // Onderwerp op SUBJECT-schaal (Portrait2.scale via de handles).
                // E27.1: de VIEW-zoom zit niet meer hier maar als camera op de
                // hele scène (EditorView). Tot de frame-vorm geclipt (cirkel =
                // transparante hoeken).
                Image(nsImage: image)
                    .resizable()
                    // Perf: .medium i.p.v. .high — bij camera-pan/zoom wordt het
                    // beeld elke frame opnieuw geresampled; .medium is op een
                    // foto-cutout op edit-zoom vrijwel niet te onderscheiden en
                    // veel goedkoper (zelfde keuze als de board, E27.6).
                    .interpolation(.medium)
                    .frame(width: imgW, height: imgH)
                    .position(x: imgCenter.x, y: imgCenter.y)
                    .frame(width: side, height: side)
                    .clipShape(clip)
                    // E33/R2: alpha-bewuste hit-test. Een tik op een OPAQUE
                    // (persoon)pixel selecteert het ONDERWERP → handles. Een tik op
                    // een TRANSPARANTE pixel binnen de vorm (lege achtergrond) houdt
                    // enkel het FRAME geselecteerd (geen handles). De clip blijft het
                    // hit-gebied; alpha beslist onderwerp vs. frame. `location` zit in
                    // de lokale `side × side`-ruimte — dezelfde ruimte als imgCenter,
                    // dus geen drift met de imgW/imgH/imgCenter-layoutmath.
                    .contentShape(clip)
                    .onTapGesture(count: 1, coordinateSpace: .local) { location in
                        selectFromTap(
                            at: location,
                            imageRect: CGRect(
                                x: imgCenter.x - imgW / 2, y: imgCenter.y - imgH / 2,
                                width: imgW, height: imgH
                            )
                        )
                    }
                    // E24.32: de pan-drag hangt nu op het ONDERWERP (niet de hele
                    // box), zodat een klik in de marge/hoeken altijd de
                    // deselect-tap (Color.clear, onder) bereikt — ook direct ná
                    // een drag (geen container-gesture die de tap opslokt).
                    .gesture(dragGesture(canvasSide: side))

                // E24.19: uitlijn-gids als VAST doel-overlay — buiten de
                // scaleEffect/clip en op canvasmaat, dus hij schaalt/beweegt NIET
                // mee met de afbeelding of de view-zoom én wordt NIET door de
                // frame-vorm afgekapt (volle canvas). De afbeelding lijnt
                // hiernaartoe uit (auto-align mikt op dezelfde FramingConstants).
                // Zichtbaar zodra de grid-toggle aan staat — ook als de
                // afbeelding niet geselecteerd is.
                AlignmentGuideOverlay2(
                    isVisible: gridEnabled || debugShowGuide,
                    inverseCameraScale: inverseCameraScale
                )
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)

                // E27.3: de selectie-handles + het kader + de ESC-deselect zijn
                // verhuisd naar een SCREEN-SPACE overlay (CanvasTransformOverlay,
                // in EditorView) — buiten de camera-transform én buiten deze
                // canvas-clip, zodat ze op élk zoomniveau even groot blijven en
                // (bij een groot-geschaald onderwerp) zichtbaar/grijpbaar worden
                // door uit te zoomen. Deze view houdt alleen het onderwerp + de
                // deselect-tap + de pan-/dubbelklik-gestures (E24.32 intact).
            }
            // E27.1: pinch/scroll-VIEW-zoom is verhuisd naar de camera (op de
            // hele scène, EditorView). De pan-drag zit op het onderwerp (E24.32);
            // dubbelklik = auto-frame/fit van het ONDERWERP (los van de camera).
            .onTapGesture(count: 2) {
                resetToFit()
            }
            .clipped()
            #if DEBUG
            // E24.17/24.19 smoke-haken: forceer de geselecteerde staat resp. de
            // (vaste) uitlijn-gids zichtbaar.
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("--select-subject") { isSelected = true }
                if args.contains("--show-guide") { debugShowGuide = true }
            }
            #endif
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Transform-state (persistent op Portrait2, anders lokaal)

    private func currentTransform() -> CanvasTransform {
        if let portrait {
            return CanvasTransform(offsetX: portrait.offsetX, offsetY: portrait.offsetY, scale: portrait.scale)
        }
        return localTransform
    }

    private func writeTransform(_ t: CanvasTransform, touch: Bool) {
        if let portrait {
            portrait.offsetX = t.offsetX
            portrait.offsetY = t.offsetY
            portrait.scale = t.scale
            if touch { portrait.touch() }
        } else {
            localTransform = t
        }
    }

    /// scale 0 = nog geen transform → fit-met-marge (beeld past binnen het
    /// canvas, gecentreerd, met frame-ademruimte) — gelijkgetrokken met
    /// AutoFramer.fitTransform (E24.18). Voorheen FILL (edge-to-edge).
    private func resolvedTransform() -> CanvasTransform {
        let c = currentTransform()
        // Gedeelde resolver (AutoFramer) zodat de Original-achtergrondlaag in
        // EditorView exact dezelfde plaatsing kan berekenen — geen drift.
        let r = AutoFramer.resolvedTransform(
            offsetX: c.offsetX, offsetY: c.offsetY, scale: c.scale, cutoutSize: image.size
        )
        return CanvasTransform(offsetX: r.offsetX, offsetY: r.offsetY, scale: r.scale)
    }

    private func fitTransform() -> CanvasTransform {
        // E24.18: padded FIT (marge in circle én square). Canonieke berekening:
        // AutoFramer.fitTransform (gedeeld; voorheen hier 1-op-1 gedupliceerd).
        let t = AutoFramer.fitTransform(cutoutSize: image.size)
        return CanvasTransform(offsetX: t.offset.width, offsetY: t.offset.height, scale: t.scale)
    }

    private func resetToFit() {
        // Dubbelklik = auto-frame (E06.5): echte AutoAligner-port wanneer
        // er een model + CGImage is; anders fill-fit.
        guard let portrait,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            withAnimation(.spring(duration: 0.35)) {
                writeTransform(fitTransform(), touch: true)
            }
            return
        }
        Task { await AutoFramer.apply(to: portrait, image: cg, undoManager: undoManager) }
    }

    // MARK: - Drag = pan + snap (v1-port)

    private func dragGesture(canvasSide: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                var t = resolvedTransform()
                if dragStart == nil {
                    dragStart = CGSize(width: t.offsetX, height: t.offsetY)
                    if let portrait { dragBefore = TransformUndo.snapshot(of: portrait) }
                    isDragging = true
                    isPanning = true
                    lastHapticTickX = t.offsetX
                    lastHapticTickY = t.offsetY
                }

                // Schermdelta → canvasruimte (1024 units breed).
                let factor = FramingConstants.editCanvas.width / canvasSide
                var dx = value.translation.width * factor
                var dy = value.translation.height * factor

                // Shift = dominante as (Figma/Instagram-conventie, v1).
                if NSEvent.modifierFlags.contains(.shift) {
                    if abs(value.translation.width) >= abs(value.translation.height) {
                        dy = 0
                    } else {
                        dx = 0
                    }
                }

                let rawX = dragStart!.width + dx
                let rawY = dragStart!.height + dy

                // Snap met hysterese: enter 12, exit 24 canvas-units.
                let canvasCenter = FramingConstants.editCanvas.width / 2
                var newX = rawX
                var newY = rawY
                var newSnappedX = snappedX
                var newSnappedY = snappedY

                let imgW = image.size.width * t.scale
                let imgH = image.size.height * t.scale
                let rawCenterX = rawX + imgW / 2
                let rawCenterY = rawY + imgH / 2

                let thresholdX = snappedX ? snapExit : snapEnter
                if abs(rawCenterX - canvasCenter) < thresholdX {
                    newX = canvasCenter - imgW / 2
                    newSnappedX = true
                } else {
                    newSnappedX = false
                }

                let thresholdY = snappedY ? snapExit : snapEnter
                if abs(rawCenterY - canvasCenter) < thresholdY {
                    newY = canvasCenter - imgH / 2
                    newSnappedY = true
                } else {
                    newSnappedY = false
                }

                // Snap-overgang = .alignment ("klikt vast"); gewone beweging
                // een zachte .generic-tick per hapticStep units (v1).
                let snapChanged = (newSnappedX != snappedX) || (newSnappedY != snappedY)
                if snapChanged {
                    haptics.perform(.alignment, performanceTime: .now)
                    lastHapticTickX = newX
                    lastHapticTickY = newY
                } else if abs(newX - lastHapticTickX) >= hapticStep
                    || abs(newY - lastHapticTickY) >= hapticStep {
                    haptics.perform(.generic, performanceTime: .now)
                    lastHapticTickX = newX
                    lastHapticTickY = newY
                }
                snappedX = newSnappedX
                snappedY = newSnappedY

                t.offsetX = newX
                t.offsetY = newY
                writeTransform(t, touch: false)
            }
            .onEnded { _ in
                if dragStart != nil {
                    // Eén touch + één undo-stap per afgeronde drag.
                    writeTransform(resolvedTransform(), touch: true)
                    registerUndo(from: dragBefore, actionName: "Move")
                }
                dragStart = nil
                dragBefore = nil
                isDragging = false
                isPanning = false
                snappedX = false
                snappedY = false
            }
    }

    private func registerUndo(from before: TransformUndo.Snapshot?, actionName: String) {
        guard let portrait, let before else { return }
        TransformUndo.register(
            undoManager,
            portrait: portrait,
            undoTo: before,
            redoTo: TransformUndo.snapshot(of: portrait),
            actionName: actionName
        )
    }

    /// E33/R2: routeer een tik op het cutout via alpha (FigJam-model).
    /// `location` zit in de lokale `side × side`-ruimte; `imageRect` is het getoonde
    /// beeld-rect in diezelfde ruimte (imgW/imgH rond imgCenter). Opaque persoon-
    /// pixel → onderwerp selecteren (handles). Transparante pixel (of buiten het
    /// beeld-rect, dus per definitie leeg) → enkel het frame geselecteerd houden.
    private func selectFromTap(at location: CGPoint, imageRect: CGRect) {
        guard imageRect.width > 0, imageRect.height > 0, imageRect.contains(location) else {
            isSelected = false      // binnen de vorm maar buiten het beeld → leeg
            return
        }
        let u = (location.x - imageRect.minX) / imageRect.width
        let v = (location.y - imageRect.minY) / imageRect.height
        if image.isOpaqueAtNormalizedPoint(u: u, v: v) {
            isSelected = true       // persoon-pixel → onderwerp + handles
        } else {
            isSelected = false      // transparante achtergrond ín het frame
        }
    }

}

// MARK: - Alpha-bewuste hit-test (R2 / E33)

// `internal` (geen `private`) zodat de genormaliseerde-punt-geometrie (de
// y-flip in E27.8) in Avatar2Tests getoetst kan worden.
extension NSImage {
    /// Is het cutout OPAQUE (= persoon aanwezig) op een genormaliseerd punt?
    /// `u`,`v` in [0,1], ORIGIN LINKSBOVEN (v groeit naar beneden — gelijk aan de
    /// SwiftUI-tik én de imgW/imgH/imgCenter-layoutmath). E27.8: sampelt ALLEEN de
    /// doelpixel via een 1×1-context (O(1), ongeacht de beeldmaat) i.p.v. het hele
    /// bitmap te materialiseren. Faalt VEILIG: elk nil-pad geeft `true` (= behandel
    /// als onderwerp) → behoudt het oude "klik = onderwerp"-gedrag.
    func isOpaqueAtNormalizedPoint(u: CGFloat, v: CGFloat, alphaThreshold: CGFloat = 0.06) -> Bool {
        guard u >= 0, u <= 1, v >= 0, v <= 1,
              let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return true }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return true }
        let px = min(w - 1, max(0, Int((u * CGFloat(w - 1)).rounded())))
        let py = min(h - 1, max(0, Int((v * CGFloat(h - 1)).rounded())))
        // E27.8: `NSBitmapImageRep(cgImage:).colorAt` op een full-res cutout (≈2048px →
        // ~16MB bitmap-unpack + per-call colorspace-conversie) hing de tik-handler ~1s
        // op. Hier tekenen we het CGImage verschoven in een 1×1-context zodat doelpixel
        // (px,py) op de enige output-pixel valt; CG clipt naar 1 pixel → constante tijd.
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return true }
        ctx.interpolationQuality = .none
        // CGContext-origin = linksONDER; rij py (origin linksboven) ligt op CG-y =
        // h-1-py. Verschuif het beeld zo dat die pixel op de output-pixel (0,0) valt.
        ctx.draw(cg, in: CGRect(x: -px, y: -(h - 1 - py), width: w, height: h))
        return CGFloat(pixel[3]) / 255 > alphaThreshold
    }
}

// MARK: - Uitlijn-gids (E24.35 — gezichtsvorm + oog-markers, DS-stijl)

/// VASTE doel-overlay: een rustige GEZICHT-silhouet (hoofd-ovaal) met twee
/// oog-markers op de standaard-positie (FramingConstants). Géén rule-of-thirds-
/// lijnen meer (24.35) — de gebruiker ziet meteen waar het hoofd/de ogen horen
/// te landen; de afbeelding lijnt hiernaartoe uit (auto-align mikt op dezelfde
/// constants). Action-lime, subtiel. Wordt BOVEN de frame-clip gerenderd en op
/// canvasmaat geframed → niet afgekapt op de cirkel-/frame-rand. Fade 0,15 s.
struct AlignmentGuideOverlay2: View {
    let isVisible: Bool
    /// E27.3: 1/camera-zoom (E27.1) — de gids zit ín de scène en schaalt mee. De
    /// silhouet-VORM volgt de frame-positie (zoomt mee), maar lijn-diktes/marker-
    /// maten worden door deze factor gedeeld zodat ze op élk zoomniveau even
    /// dun/groot op het scherm blijven.
    var inverseCameraScale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let inv = inverseCameraScale

            // Doel-posities uit FramingConstants (ogen op de bovenste derde).
            let centerX = FramingConstants.targetEyeCenterX * side
            let eyeY = FramingConstants.targetEyeCenterY * side
            let headCenterY = FramingConstants.targetFaceCenterY * side
            let headHeight = FramingConstants.targetFaceHeightRatio * side
            let headWidth = headHeight * 0.74
            let interEye = FramingConstants.targetInterEyeRatio * side
            let eyeDiameter = max(3, side * 0.022) * inv

            ZStack {
                // Hoofd/gezicht-silhouet — een rustig ovaal als doelvorm.
                Ellipse()
                    .stroke(DSColor.Action.primary.opacity(0.8), lineWidth: 1.5 * inv)
                    .frame(width: headWidth, height: headHeight)
                    .position(x: centerX, y: headCenterY)

                // Twee oog-markers op de ooglijn (interoog-afstand uit constants).
                ForEach([-1.0, 1.0], id: \.self) { sign in
                    Circle()
                        .fill(DSColor.Action.primary)
                        .frame(width: eyeDiameter, height: eyeDiameter)
                        .position(x: centerX + CGFloat(sign) * interEye / 2, y: eyeY)
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.25), radius: 1 * inv)
            .opacity(isVisible ? 1 : 0)
            .animation(DSMotion.fast, value: isVisible)
        }
        .allowsHitTesting(false)
    }
}
