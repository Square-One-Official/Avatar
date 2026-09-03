// Automatic framing (E06.5) — 1-op-1 port van v1 AutoAligner + de
// detectiehelpers uit v1 ImageProcessor (ProcessedSubject leeft in
// Avatar/Services, niet in AvatarKit — board-context gecorrigeerd in de
// story). Doelwaarden zijn de getunede v1-waarden uit FramingConstants:
// ogen op de standaard-ooglijn (0.37), interoog = 12% van de canvashoogte,
// face-rect-fallback 0.38/0.42, body-overshoot 3% als minimum-scale.
//
// computeTransform is puur (unit-getest); detectie draait via Vision
// off-main. De actie schrijft het resultaat op Portrait2 — het
// E06.4-canvas observeert het model en animeert de overgang.

import AvatarUI
import CoreGraphics
import Foundation
import SwiftUI
import Vision

enum AutoFramer {

    struct Metrics {
        var faceRect: CGRect?
        var eyeCenter: CGPoint?
        var interEyeDistance: CGFloat?
        var bodyBottomY: CGFloat
        /// Opaque-pixel bbox in top-left pixel coordinates. Nil when the
        /// cutout is fully transparent. Used so voluminous effects (Hairy,
        /// Windy) frame the whole subject instead of the face alone.
        var contentRect: CGRect?
        /// Opaque-pixel bbox of the rows above the chin (face.maxY) — hair
        /// and any halo, never the shoulders. Nil without a face.
        var headContentRect: CGRect?
    }

    struct Transform: Equatable {
        var scale: CGFloat
        var offset: CGSize
    }

    /// Landmark-invoer voor set-brede Match framing (gelijke IPD + geen lege onderkant).
    struct FramingSubject: Equatable {
        var faceRect: CGRect?
        var eyeCenter: CGPoint?
        var interEyeDistance: CGFloat?
        var bodyBottomY: CGFloat
        var cutoutSize: CGSize
    }

    // MARK: - Pure math (v1 AutoAligner.computeTransform)

    static func computeTransform(
        faceRect: CGRect?,
        eyeCenter: CGPoint? = nil,
        interEyeDistance: CGFloat? = nil,
        cutoutSize: CGSize,
        bodyBottomY: CGFloat = 0,
        contentRect: CGRect? = nil,
        headContentRect: CGRect? = nil,
        canvas: CGSize = FramingConstants.editCanvas
    ) -> Transform {
        guard let faceRect, faceRect.height > 0 else {
            // Geen gezicht: centreer het onderwerp (alpha-bbox), niet het PNG.
            // Hairy/Windy zonder detecteerbaar gezicht zou anders off-center
            // in een te groot canvas blijven staan.
            if let contentRect, contentRect.width > 0, contentRect.height > 0 {
                return fitContent(contentRect, canvas: canvas)
            }
            return fitTransform(cutoutSize: cutoutSize, canvas: canvas)
        }

        let anchorX: CGFloat
        let anchorY: CGFloat
        let targetCX: CGFloat
        let targetCY: CGFloat
        var scale: CGFloat

        if let eyeCenter, let ied = interEyeDistance, ied > 0 {
            // Eye-based (voorkeur): ooglijn + vaste interoogafstand.
            anchorX = eyeCenter.x
            anchorY = eyeCenter.y
            targetCX = canvas.width * FramingConstants.targetEyeCenterX
            targetCY = canvas.height * FramingConstants.targetEyeCenterY
            let effectiveIED = effectiveInterEyeDistance(ied, faceRect: faceRect)
            scale = (canvas.height * FramingConstants.targetInterEyeRatio) / effectiveIED
        } else {
            // Fallback: face-rect-centrum.
            anchorX = faceRect.midX
            anchorY = faceRect.midY
            targetCX = canvas.width * FramingConstants.targetFaceCenterX
            targetCY = canvas.height * FramingConstants.targetFaceCenterY
            scale = (canvas.height * FramingConstants.targetFaceHeightRatio) / faceRect.height
        }

        // Body-bewust minimum: romp loopt tot voorbij de canvasonderkant
        // (+ kleine overshoot) zodat niemand "zwevend" eindigt.
        if bodyBottomY > anchorY {
            let requiredBottom = canvas.height * (1.0 + FramingConstants.bodyOvershoot)
            let minScale = (requiredBottom - targetCY) / (bodyBottomY - anchorY)
            scale = max(scale, minScale)
        }

        let preferred = Transform(
            scale: scale,
            offset: CGSize(
                width: targetCX - anchorX * scale,
                height: targetCY - anchorY * scale
            )
        )

        // Volumineus effect (Hairy-halo, Windy-haar omhoog): eye-based
        // knipt de extra massa af. Alleen dan terugvallen op een padded
        // content-fit. Gemeten op de hoofdband (rijen boven de kin) zodat
        // normale schouders/romp nooit meetellen — een gewoon portret houdt
        // de ooglijn + body-overshoot, ook als de haartop of de schouders
        // een fractie buiten het canvas vallen (v1-gedrag).
        if let contentRect,
           contentRect.width > 0, contentRect.height > 0 {
            let head = headContentRect ?? contentRect
            if head.width > 0, head.height > 0,
               contentShouldLeadFraming(face: faceRect, head: head),
               contentOverflowsTopOrSides(head, preferred, canvas: canvas) {
                return fitContent(contentRect, canvas: canvas)
            }
        }
        return preferred
    }

    /// Interoogafstand voor de schaal, met de face-box-hoogte als ondergrens.
    /// Een gedraaid hoofd (driekwart-profiel) meet in 2D een kleinere
    /// pupilafstand (× cos(yaw)) terwijl de boxhoogte gelijk blijft; zonder
    /// deze grens zoomt de eye-based schaal zo'n portret ver in — zichtbaar in
    /// Match framing als één "te groot" hoofd naast frontale collega's.
    /// Frontale gezichten zitten boven de grens en houden hun echte IPD.
    static func effectiveInterEyeDistance(_ interEyeDistance: CGFloat, faceRect: CGRect) -> CGFloat {
        max(interEyeDistance, faceRect.height * FramingConstants.minInterEyeToFaceHeight)
    }

    /// Padded fit van een onderwerp-bbox (niet het volledige PNG). De
    /// content-oorsprong wordt in de offset verrekend zodat het onderwerp
    /// in het canvas midden landt.
    static func fitContent(_ content: CGRect, canvas: CGSize = FramingConstants.editCanvas) -> Transform {
        let fitted = fitTransform(cutoutSize: content.size, canvas: canvas)
        return Transform(
            scale: fitted.scale,
            offset: CGSize(
                width: fitted.offset.width - content.minX * fitted.scale,
                height: fitted.offset.height - content.minY * fitted.scale
            )
        )
    }

    /// Extra massa rond het hoofd — niet gewoon haar. De Vision-face-box
    /// loopt van wenkbrauwen tot kin, dus normaal haar steekt er al
    /// ~0.3–0.6× de boxhoogte boven en ~0.5× de boxbreedte naast uit; lang
    /// haar tot ~0.7×. Een Hairy-halo zit ruim boven 1×.
    private static func contentShouldLeadFraming(face: CGRect, head: CGRect) -> Bool {
        let faceH = max(face.height, 1)
        let faceW = max(face.width, 1)
        let above = face.minY - head.minY
        let extraLeft = face.minX - head.minX
        let extraRight = head.maxX - face.maxX
        return above > faceH * 0.9
            || extraLeft > faceW * 0.9
            || extraRight > faceW * 0.9
            || head.width > faceW * 2.8
    }

    /// Eye-based transform knipt de hoofdband aan de bovenkant of zijkanten
    /// (onderkant mag: body-overshoot is bewust). Tolerantie 3% van het
    /// canvas: de alpha-bbox is grof gesampled en een paar px haar buiten
    /// het frame is geen reden om de ooglijn los te laten.
    private static func contentOverflowsTopOrSides(
        _ content: CGRect, _ transform: Transform, canvas: CGSize
    ) -> Bool {
        let tolerance = min(canvas.width, canvas.height) * 0.03
        let top = content.minY * transform.scale + transform.offset.height
        let left = content.minX * transform.scale + transform.offset.width
        let right = content.maxX * transform.scale + transform.offset.width
        return top < -tolerance
            || left < -tolerance
            || right > canvas.width + tolerance
    }

    /// Eén bron van waarheid voor de "resolved" canvas-transform: de persistente
    /// transform (offsetX/offsetY/scale in 1024-units) als `scale > 0`, anders de
    /// gedeelde padded fit-fallback. Zo krijgen het cutout (EditorCanvasView) én de
    /// Original-achtergrondlaag (EditorView.backgroundLayer) EXACT dezelfde
    /// plaatsing — geen drift, geen dubbel onderwerp.
    static func resolvedTransform(
        offsetX: Double, offsetY: Double, scale: Double,
        cutoutSize: CGSize, canvas: CGSize = FramingConstants.editCanvas
    ) -> (offsetX: Double, offsetY: Double, scale: Double) {
        if scale > 0 { return (offsetX, offsetY, scale) }
        let t = fitTransform(cutoutSize: cutoutSize, canvas: canvas)
        return (Double(t.offset.width), Double(t.offset.height), Double(t.scale))
    }

    /// Gedeelde schaal voor een set: dezelfde camera-afstand (gelijke IPD op
    /// het canvas) én geen lege onderkant. Per portret geldt
    /// `scale = canonical × sharedBoost`, waarbij `sharedBoost` groot genoeg
    /// is zodat het kortste lichaam nog tot voorbij de canvasonderkant reikt.
    /// Portretten zonder gezicht vallen terug op `fitTransform` (niet meegenomen
    /// in de boost). Editor Auto-frame blijft `computeTransform` (per portret).
    static func computeSharedTransforms(
        _ subjects: [FramingSubject],
        canvas: CGSize = FramingConstants.editCanvas
    ) -> [Transform] {
        struct Prep {
            var hasFace: Bool
            var anchorX: CGFloat
            var anchorY: CGFloat
            var targetCX: CGFloat
            var targetCY: CGFloat
            var canonicalScale: CGFloat
            var bodyMinScale: CGFloat?
            var cutoutSize: CGSize
        }

        let requiredBottom = canvas.height * (1.0 + FramingConstants.bodyOvershoot)
        let preps: [Prep] = subjects.map { subject in
            guard let faceRect = subject.faceRect, faceRect.height > 0 else {
                return Prep(
                    hasFace: false, anchorX: 0, anchorY: 0,
                    targetCX: 0, targetCY: 0, canonicalScale: 1,
                    bodyMinScale: nil, cutoutSize: subject.cutoutSize
                )
            }

            let anchorX: CGFloat
            let anchorY: CGFloat
            let targetCX: CGFloat
            let targetCY: CGFloat
            let canonicalScale: CGFloat

            if let eyeCenter = subject.eyeCenter,
               let ied = subject.interEyeDistance, ied > 0 {
                anchorX = eyeCenter.x
                anchorY = eyeCenter.y
                targetCX = canvas.width * FramingConstants.targetEyeCenterX
                targetCY = canvas.height * FramingConstants.targetEyeCenterY
                let effectiveIED = effectiveInterEyeDistance(ied, faceRect: faceRect)
                canonicalScale = (canvas.height * FramingConstants.targetInterEyeRatio) / effectiveIED
            } else {
                anchorX = faceRect.midX
                anchorY = faceRect.midY
                targetCX = canvas.width * FramingConstants.targetFaceCenterX
                targetCY = canvas.height * FramingConstants.targetFaceCenterY
                canonicalScale = (canvas.height * FramingConstants.targetFaceHeightRatio) / faceRect.height
            }

            var bodyMinScale: CGFloat?
            if subject.bodyBottomY > anchorY {
                bodyMinScale = (requiredBottom - targetCY) / (subject.bodyBottomY - anchorY)
            }

            return Prep(
                hasFace: true, anchorX: anchorX, anchorY: anchorY,
                targetCX: targetCX, targetCY: targetCY,
                canonicalScale: canonicalScale, bodyMinScale: bodyMinScale,
                cutoutSize: subject.cutoutSize
            )
        }

        let sharedBoost = preps.reduce(CGFloat(1)) { current, prep in
            guard prep.hasFace, let minScale = prep.bodyMinScale, prep.canonicalScale > 0 else {
                return current
            }
            return max(current, minScale / prep.canonicalScale)
        }

        return preps.map { prep in
            guard prep.hasFace else {
                return fitTransform(cutoutSize: prep.cutoutSize, canvas: canvas)
            }
            let scale = prep.canonicalScale * sharedBoost
            return Transform(
                scale: scale,
                offset: CGSize(
                    width: prep.targetCX - prep.anchorX * scale,
                    height: prep.targetCY - prep.anchorY * scale
                )
            )
        }
    }

    /// Sticker-fix (2026-09-02): vrijstaande gesloten vorm (die-cut-sticker).
    /// Geen ooglijn + body-overshoot — die duwt de gesloten onderrand (mét
    /// witte rand) uit beeld — maar de alpha-bbox gecentreerd met de
    /// standaard ademruimte. Zonder bbox: het hele PNG passend.
    static func freestandingTransform(
        contentRect: CGRect?,
        cutoutSize: CGSize,
        canvas: CGSize = FramingConstants.editCanvas
    ) -> Transform {
        if let contentRect, contentRect.width > 0, contentRect.height > 0 {
            return fitContent(contentRect, canvas: canvas)
        }
        return fitTransform(cutoutSize: cutoutSize, canvas: canvas)
    }

    /// Geen gezicht: cutout passend met marge, gecentreerd (v1-fallback).
    static func fitTransform(
        cutoutSize: CGSize,
        canvas: CGSize = FramingConstants.editCanvas
    ) -> Transform {
        guard cutoutSize.width > 0, cutoutSize.height > 0 else {
            return Transform(scale: 1, offset: .zero)
        }
        // E24.18: gedeelde frame-ademruimte-padding (was hier hardcoded 0.85).
        let padding = FramingConstants.frameFitPadding
        let scale = min(canvas.width / cutoutSize.width, canvas.height / cutoutSize.height) * padding
        return Transform(
            scale: scale,
            offset: CGSize(
                width: (canvas.width - cutoutSize.width * scale) / 2,
                height: (canvas.height - cutoutSize.height * scale) / 2
            )
        )
    }

    // MARK: - Detectie (Vision, off-main aan te roepen)

    static func metrics(for image: CGImage) -> Metrics {
        var metrics = Metrics(bodyBottomY: 0, contentRect: nil, headContentRect: nil)

        // Gezicht + lichaam in één Vision-pass (twee aparte handlers waren ~2× zo traag).
        let faceRequest = VNDetectFaceLandmarksRequest()
        let bodyRequest = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        _ = try? handler.perform([faceRequest, bodyRequest])

        if let observations = faceRequest.results, !observations.isEmpty {
            let imgW = CGFloat(image.width)
            let imgH = CGFloat(image.height)
            let largest = observations.max {
                $0.boundingBox.width * $0.boundingBox.height
                    < $1.boundingBox.width * $1.boundingBox.height
            }!
            let bb = largest.boundingBox
            metrics.faceRect = CGRect(
                x: bb.origin.x * imgW,
                y: (1.0 - bb.origin.y - bb.height) * imgH,
                width: bb.width * imgW,
                height: bb.height * imgH
            )

            func regionCenter(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
                guard let region, region.pointCount > 0 else { return nil }
                let pts = region.normalizedPoints
                var sumX: CGFloat = 0, sumY: CGFloat = 0
                for i in 0..<region.pointCount {
                    sumX += pts[i].x
                    sumY += pts[i].y
                }
                let avgX = sumX / CGFloat(region.pointCount)
                let avgY = sumY / CGFloat(region.pointCount)
                return CGPoint(
                    x: (bb.origin.x + avgX * bb.width) * imgW,
                    y: (1.0 - (bb.origin.y + avgY * bb.height)) * imgH
                )
            }

            if let landmarks = largest.landmarks,
               let left = regionCenter(landmarks.leftPupil) ?? regionCenter(landmarks.leftEye),
               let right = regionCenter(landmarks.rightPupil) ?? regionCenter(landmarks.rightEye) {
                metrics.eyeCenter = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
                metrics.interEyeDistance = hypot(right.x - left.x, right.y - left.y)
            }
        }

        // Onderkant lichaam: body-pose (zelfde pass), anders de alpha-bbox.
        // Eén alpha-sample voor onderwerp-bbox én hoofdband (rijen boven de kin).
        let sampler = AlphaSampler(image: image)
        let content = sampler?.bbox()
        metrics.contentRect = content
        if let sampler, let face = metrics.faceRect {
            let chin = max(0, min(image.height, Int(face.maxY.rounded())))
            metrics.headContentRect = sampler.bbox(rows: 0..<chin)
        }
        metrics.bodyBottomY = bodyPoseBottom(from: bodyRequest.results?.first, imageHeight: image.height)
            ?? content?.maxY
            ?? 0
        return metrics
    }

    private static func bodyPoseBottom(from observation: VNHumanBodyPoseObservation?, imageHeight: Int) -> CGFloat? {
        guard let observation else { return nil }
        let imgH = CGFloat(imageHeight)
        var lowestY: CGFloat = 0
        for jointName in observation.availableJointNames {
            guard let point = try? observation.recognizedPoint(jointName),
                  point.confidence > 0.1 else { continue }
            lowestY = max(lowestY, (1.0 - point.location.y) * imgH)
        }
        return lowestY > 0 ? lowestY : nil
    }

    /// Opaque-pixel bbox (top-left). Samplet een grof raster (~64 stappen per
    /// as) — genoeg voor framing, niet voor pixel-exacte silhouetten. Zachte
    /// haarranden (alpha > 8) tellen mee, anders knipt Hairy de halo af.
    static func contentRectFromAlpha(of image: CGImage, threshold: UInt8 = 8) -> CGRect? {
        AlphaSampler(image: image)?.bbox(threshold: threshold)
    }

    /// Hoofdband-bbox: opaque pixels in de rijen boven `chinY` (top-left px).
    static func headContentRectFromAlpha(of image: CGImage, chinY: CGFloat, threshold: UInt8 = 8) -> CGRect? {
        let chin = max(0, min(image.height, Int(chinY.rounded())))
        return AlphaSampler(image: image)?.bbox(threshold: threshold, rows: 0..<chin)
    }

    /// Eén draw van de cutout naar RGBA, daarna meerdere bbox-queries op een
    /// grof raster (stap ~w/64, ~h/64).
    struct AlphaSampler {
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let stepX: Int
        let stepY: Int
        let pixels: [UInt8]

        init?(image: CGImage) {
            let w = image.width
            let h = image.height
            guard w > 0, h > 0 else { return nil }
            let bpr = w * 4
            var buffer = [UInt8](repeating: 0, count: h * bpr)
            let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
                guard let ctx = CGContext(
                    data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                    bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            width = w
            height = h
            bytesPerRow = bpr
            stepX = max(1, w / 64)
            stepY = max(1, h / 64)
            pixels = buffer
        }

        /// Bbox van de opaque pixels binnen `rows` (top-left, hele beeld als
        /// nil). Rasterhits worden tot `step-1` px naar buiten verruimd.
        func bbox(threshold: UInt8 = 8, rows: Range<Int>? = nil) -> CGRect? {
            let rowRange = (rows ?? 0..<height).clamped(to: 0..<height)
            guard !rowRange.isEmpty else { return nil }
            var minX = width, minY = height, maxX = -1, maxY = -1
            var y = rowRange.lowerBound
            while y < rowRange.upperBound {
                var x = 0
                let base = y * bytesPerRow
                while x < width {
                    if pixels[base + x * 4 + 3] > threshold {
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                    }
                    x += stepX
                }
                y += stepY
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            minX = max(0, minX - (stepX - 1))
            minY = max(rowRange.lowerBound, minY - (stepY - 1))
            maxX = min(width - 1, maxX + stepX - 1)
            maxY = min(rowRange.upperBound - 1, maxY + stepY - 1)
            return CGRect(
                x: minX, y: minY,
                width: maxX - minX + 1,
                height: maxY - minY + 1
            )
        }
    }

    /// Berekent (off-main) het auto-frame-transform voor een cutout —
    /// gebruikt door de editor "Auto-frame & center" (E06.5).
    static func transform(forCutout image: CGImage) async -> Transform {
        let m = await Task.detached(priority: .userInitiated) {
            Self.metrics(for: image)
        }.value
        return computeTransform(
            faceRect: m.faceRect,
            eyeCenter: m.eyeCenter,
            interEyeDistance: m.interEyeDistance,
            cutoutSize: CGSize(width: image.width, height: image.height),
            bodyBottomY: m.bodyBottomY,
            contentRect: m.contentRect,
            headContentRect: m.headContentRect
        )
    }

    /// Off-main detectie + `computeSharedTransforms` voor Match framing.
    static func sharedTransforms(for images: [CGImage]) async -> [Transform] {
        let subjects: [FramingSubject] = await Task.detached(priority: .userInitiated) {
            images.map { image in
                let m = Self.metrics(for: image)
                return FramingSubject(
                    faceRect: m.faceRect,
                    eyeCenter: m.eyeCenter,
                    interEyeDistance: m.interEyeDistance,
                    bodyBottomY: m.bodyBottomY,
                    cutoutSize: CGSize(width: image.width, height: image.height)
                )
            }
        }.value
        return computeSharedTransforms(subjects)
    }

    // MARK: - Actie

    /// `portrait` = gezicht/ooglijn + body-overshoot (default); `freestanding` =
    /// content-fit van de alpha-bbox (die-cut-sticker, geen Vision nodig).
    enum Mode: Equatable, Sendable {
        case portrait
        case freestanding
    }

    /// Bereken en schrijf het auto-frame-transform voor dit portret; de
    /// geanimeerde overgang komt uit de withAnimation rond de model-writes
    /// (het E06.4-canvas observeert Portrait2).
    @MainActor
    static func apply(
        to portrait: Portrait2, image: CGImage, undoManager: UndoManager? = nil,
        mode: Mode = .portrait
    ) async {
        let size = CGSize(width: image.width, height: image.height)
        let before = TransformUndo.snapshot(of: portrait)
        let transform: Transform
        switch mode {
        case .freestanding:
            let content = await Task.detached(priority: .userInitiated) {
                Self.contentRectFromAlpha(of: image)
            }.value
            transform = freestandingTransform(contentRect: content, cutoutSize: size)
        case .portrait:
            let metrics = await Task.detached(priority: .userInitiated) {
                Self.metrics(for: image)
            }.value
            transform = computeTransform(
                faceRect: metrics.faceRect,
                eyeCenter: metrics.eyeCenter,
                interEyeDistance: metrics.interEyeDistance,
                cutoutSize: size,
                bodyBottomY: metrics.bodyBottomY,
                contentRect: metrics.contentRect,
                headContentRect: metrics.headContentRect
            )
        }
        DSMotion.animate(DSMotion.springTransform) {
            portrait.offsetX = transform.offset.width
            portrait.offsetY = transform.offset.height
            portrait.scale = transform.scale
        }
        portrait.touch()
        TransformUndo.register(
            undoManager,
            portrait: portrait,
            undoTo: before,
            redoTo: TransformUndo.snapshot(of: portrait),
            actionName: "Automatic Framing"
        )
    }
}
