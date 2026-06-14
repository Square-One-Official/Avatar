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
    /// E24.8: VIEW-zoom (efemere viewport-zoom, 1×–maxViewZoom). Leeft in
    /// EditorView zodat de zoom-HUD búiten de frame-clip (24.16) kan renderen.
    /// Losgekoppeld van de SUBJECT-schaal (Portrait2.scale, via de handles).
    @Binding var viewZoom: Double
    let maxViewZoom: Double
    /// E24.16/24.8: de frame-vorm clipt het BEELD (niet de handles), zodat de
    /// selectie-handles bij een cirkel-frame zichtbaar/bruikbaar blijven.
    var frameShape: ExportShape = .square

    @State private var dragStart: CGSize?
    @State private var isDragging = false
    @State private var snappedX = false
    @State private var snappedY = false
    @State private var lastHapticTickX: Double = 0
    @State private var lastHapticTickY: Double = 0
    @State private var lastMagnification: Double = 1
    // E24.17: onderwerp geselecteerd → transform-handles zichtbaar (klik op de
    // afbeelding selecteert, klik erbuiten deselecteert).
    @State private var isSelected = false

    // E24.8: hoek-handle-drag schaalt het onderwerp (Portrait2.scale).
    @State private var handleStartScale: Double?
    @State private var handleStartDist: CGFloat = 0
    @State private var handleBefore: TransformUndo.Snapshot?

    // E06.2: before-snapshots zodat een afgerond gebaar één undo-stap is.
    @State private var dragBefore: TransformUndo.Snapshot?
    @Environment(\.undoManager) private var undoManager

    /// In-memory transform voor het (theoretische) geval zonder model —
    /// het canvas werkt dan gewoon, alleen zonder persistentie.
    @State private var localTransform = CanvasTransform(offsetX: 0, offsetY: 0, scale: 0)

    private let haptics = NSHapticFeedbackManager.defaultPerformer

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
                // of de marge) = deselecteren → handles weg.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isSelected = false }

                // Onderwerp + ooglijn-guide, ónder de VIEW-zoom (scaleEffect om
                // het canvasmidden) — los van de SUBJECT-schaal. Tot de
                // frame-vorm geclipt (cirkel = transparante hoeken).
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: imgW, height: imgH)
                    .position(x: imgCenter.x, y: imgCenter.y)
                    .overlay { AlignmentGuideOverlay2(isVisible: isDragging) }
                    .scaleEffect(viewZoom, anchor: .center)
                    .frame(width: side, height: side)
                    .clipShape(clip)
                    // E24.17: klik OP de afbeelding (binnen de vorm) = selecteren
                    // → transform-handles verschijnen.
                    .contentShape(clip)
                    .onTapGesture { isSelected = true }

                // E24.8/24.17: selectie-handles — alléén zichtbaar als geselecteerd.
                if isSelected {
                    handleLayer(side: side, imgW: imgW, imgH: imgH, center: imgCenter)
                }
            }
            // E24.17: pinch = canvas-VIEW-zoom (Figma/Preview). Trackpad/scroll
            // schaalt niets meer (scroll-monitor verwijderd). Pan blijft op drag.
            .gesture(dragGesture(canvasSide: side))
            .simultaneousGesture(magnifyGesture)
            .onTapGesture(count: 2) {
                resetToFit()
                withAnimation(.spring(duration: 0.3)) { viewZoom = 1 }
            }
            .coordinateSpace(name: Self.canvasSpace)
            .clipped()
            #if DEBUG
            // E24.17 smoke-haak: forceer de geselecteerde staat (handles zichtbaar).
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("--select-subject") { isSelected = true }
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
        let current = currentTransform()
        if current.scale > 0 { return current }
        return fitTransform()
    }

    private func fitTransform() -> CanvasTransform {
        let canvas = FramingConstants.editCanvas
        guard image.size.width > 0, image.size.height > 0 else {
            return CanvasTransform(offsetX: 0, offsetY: 0, scale: 1)
        }
        // E24.18: padded FIT i.p.v. FILL → het onderwerp raakt de framerand niet
        // (marge in circle én square). Zelfde padding-constante als AutoFramer.
        let scale = min(canvas.width / image.size.width, canvas.height / image.size.height)
            * FramingConstants.frameFitPadding
        return CanvasTransform(
            offsetX: (canvas.width - image.size.width * scale) / 2,
            offsetY: (canvas.height - image.size.height * scale) / 2,
            scale: scale
        )
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

    // MARK: - View-zoom (alléén pinch), 1×–maxViewZoom om het midden

    // E24.17: pinch = canvas-VIEW-zoom (efemeer, Figma/Preview-gedrag). Scroll
    // schaalt bewust NIETS meer (de scroll-monitor is verwijderd); het onderwerp
    // schalen gaat via de selectie-handles.
    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = Double(value) / max(0.0001, lastMagnification)
                lastMagnification = Double(value)
                applyViewZoom(delta: delta)
            }
            .onEnded { _ in lastMagnification = 1 }
    }

    /// E24.8: efemere viewport-zoom (1×–maxViewZoom). Geen persist, geen undo.
    private func applyViewZoom(delta: Double) {
        viewZoom = min(maxViewZoom, max(1, viewZoom * delta))
    }

    // MARK: - Selectie-handles (E24.8) — onderwerp schalen via de hoeken

    static let canvasSpace = "editorCanvas"

    /// Vier hoek-handles + selectiekader op het onderwerp; positie volgt de
    /// view-zoom (geschaald om het canvasmidden). DEFAULT-gedrag: aspect-locked,
    /// schaalt om het onderwerp-midden, op `Portrait2.scale`. De open keuzes
    /// (welke handles / aspect-lock / scale-bron / meerdere lagen) staan in
    /// DECISIONS-PENDING voor Thierry.
    @ViewBuilder
    private func handleLayer(side: CGFloat, imgW: CGFloat, imgH: CGFloat, center: CGPoint) -> some View {
        if portrait != nil {
            let canvasCenter = CGPoint(x: side / 2, y: side / 2)
            let centerS = CGPoint(
                x: canvasCenter.x + (center.x - canvasCenter.x) * viewZoom,
                y: canvasCenter.y + (center.y - canvasCenter.y) * viewZoom
            )
            let halfW = imgW / 2 * viewZoom
            let halfH = imgH / 2 * viewZoom
            let corners = [
                CGPoint(x: centerS.x - halfW, y: centerS.y - halfH),
                CGPoint(x: centerS.x + halfW, y: centerS.y - halfH),
                CGPoint(x: centerS.x - halfW, y: centerS.y + halfH),
                CGPoint(x: centerS.x + halfW, y: centerS.y + halfH),
            ]
            ZStack {
                Rectangle()
                    .strokeBorder(DSColor.Action.primary.opacity(0.7), lineWidth: 1)
                    .frame(width: halfW * 2, height: halfH * 2)
                    .position(centerS)
                    .allowsHitTesting(false)
                ForEach(0..<corners.count, id: \.self) { i in
                    handleDot(at: corners[i], imageCenterOnScreen: centerS)
                }
            }
            // Alléén tonen in rust (niet tijdens pannen) zodat ze niet storen.
            .opacity(isDragging ? 0 : 1)
            .animation(.easeOut(duration: 0.12), value: isDragging)
        }
    }

    private func handleDot(at pos: CGPoint, imageCenterOnScreen: CGPoint) -> some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(DSColor.Action.primary, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            .frame(width: 14, height: 14)
            .position(pos)
            .gesture(
                DragGesture(coordinateSpace: .named(Self.canvasSpace))
                    .onChanged { value in
                        if handleStartScale == nil {
                            handleStartScale = resolvedTransform().scale
                            handleStartDist = max(1, distance(value.startLocation, imageCenterOnScreen))
                            if let portrait { handleBefore = TransformUndo.snapshot(of: portrait) }
                        }
                        guard let startScale = handleStartScale else { return }
                        // viewZoom valt uit de verhouding (beide afstanden zijn
                        // even hard meegeschaald rond het onderwerp-midden).
                        let ratio = distance(value.location, imageCenterOnScreen) / handleStartDist
                        applySubjectScale(to: startScale * ratio)
                    }
                    .onEnded { _ in
                        if portrait != nil {
                            writeTransform(resolvedTransform(), touch: true)
                            registerUndo(from: handleBefore, actionName: "Scale")
                        }
                        handleStartScale = nil
                        handleBefore = nil
                    }
            )
    }

    /// Schaalt het onderwerp om zijn eigen midden (blijft staan), geclampt aan
    /// de fill-fit-grenzen (zelfde band als de oude pinch-zoom).
    private func applySubjectScale(to newScale: Double) {
        var t = resolvedTransform()
        let baseline = fitTransform().scale
        let clamped = min(
            baseline * FramingConstants.maxZoomFactor,
            max(baseline * FramingConstants.minZoomFactor, newScale)
        )
        guard clamped != t.scale else { return }
        let cxU = t.offsetX + image.size.width * t.scale / 2
        let cyU = t.offsetY + image.size.height * t.scale / 2
        t.offsetX = cxU - image.size.width * clamped / 2
        t.offsetY = cyU - image.size.height * clamped / 2
        t.scale = clamped
        writeTransform(t, touch: false)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

// MARK: - Guide-overlay (v1 AlignmentGuideOverlay in DS-stijl)

/// Ooglijn + oogmarkers + hoofd-ovaal op de standaard-positie
/// (FramingConstants), action-lime i.p.v. v1-cyaan. Fade 0,15 s — de
/// overlay leeft alleen tijdens een drag.
struct AlignmentGuideOverlay2: View {
    let isVisible: Bool

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let ied = FramingConstants.targetInterEyeRatio * side
            let eyeCX = FramingConstants.targetEyeCenterX * side
            let eyeCY = FramingConstants.targetEyeCenterY * side
            let ovalW = ied * 2.5
            let ovalH = ied * 3.6
            let ovalCY = eyeCY + ovalH * 0.10

            ZStack {
                // Verticale midden-X-lijn (snapdoel).
                Path { p in
                    p.move(to: CGPoint(x: side / 2, y: 0))
                    p.addLine(to: CGPoint(x: side / 2, y: side))
                }
                .stroke(DSColor.Action.primary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 0.75, dash: [4, 3]))

                // Hoofd-ovaal.
                Ellipse()
                    .stroke(DSColor.Action.primary.opacity(0.40),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: ovalW, height: ovalH)
                    .position(x: eyeCX, y: ovalCY)

                // Standaard-ooglijn.
                Path { p in
                    p.move(to: CGPoint(x: eyeCX - ovalW * 0.55, y: eyeCY))
                    p.addLine(to: CGPoint(x: eyeCX + ovalW * 0.55, y: eyeCY))
                }
                .stroke(DSColor.Action.primary.opacity(0.30),
                        style: StrokeStyle(lineWidth: 0.75, dash: [4, 3]))

                eyeMarker(at: CGPoint(x: eyeCX - ied / 2, y: eyeCY), size: ied * 0.30)
                eyeMarker(at: CGPoint(x: eyeCX + ied / 2, y: eyeCY), size: ied * 0.30)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.25), radius: 1)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: isVisible)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func eyeMarker(at center: CGPoint, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(DSColor.Action.primary.opacity(0.55), lineWidth: 1.5)
                .frame(width: size, height: size)
            Circle()
                .fill(DSColor.Action.primary.opacity(0.45))
                .frame(width: size * 0.35, height: size * 0.35)
        }
        .position(center)
    }
}
