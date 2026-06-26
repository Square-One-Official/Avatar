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
    }

    struct Transform: Equatable {
        var scale: CGFloat
        var offset: CGSize
    }

    // MARK: - Pure math (v1 AutoAligner.computeTransform)

    static func computeTransform(
        faceRect: CGRect?,
        eyeCenter: CGPoint? = nil,
        interEyeDistance: CGFloat? = nil,
        cutoutSize: CGSize,
        bodyBottomY: CGFloat = 0,
        canvas: CGSize = FramingConstants.editCanvas
    ) -> Transform {
        guard let faceRect, faceRect.height > 0 else {
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
            scale = (canvas.height * FramingConstants.targetInterEyeRatio) / ied
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

        return Transform(
            scale: scale,
            offset: CGSize(
                width: targetCX - anchorX * scale,
                height: targetCY - anchorY * scale
            )
        )
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
        var metrics = Metrics(bodyBottomY: 0)

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

        // Onderkant lichaam: body-pose (zelfde pass), anders gesamplede alpha-scan.
        metrics.bodyBottomY = bodyPoseBottom(from: bodyRequest.results?.first, imageHeight: image.height)
            ?? contentBottomFromAlpha(of: image)
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

    /// Alpha-scan van onder naar boven (v1-fallback bij mislukte pose).
    /// Samplet horizontaal (stap ~w/64) — volledige kolom-scan was tot ~64× trager.
    private static func contentBottomFromAlpha(of image: CGImage) -> CGFloat? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }
        let bpr = w * 4
        var pixels = [UInt8](repeating: 0, count: h * bpr)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let sampleStep = max(1, w / 64)
        for row in stride(from: h - 1, through: 0, by: -1) {
            let base = row * bpr
            for col in stride(from: 0, to: w, by: sampleStep) where pixels[base + col * 4 + 3] > 20 {
                return CGFloat(row)
            }
        }
        return nil
    }

    /// Berekent (off-main) het auto-frame-transform voor een cutout —
    /// gebruikt door de set-brede "Align set" (E05.7) die zelf de
    /// undo-groepering en het schrijven verzorgt.
    static func transform(forCutout image: CGImage) async -> Transform {
        let m = await Task.detached(priority: .userInitiated) {
            Self.metrics(for: image)
        }.value
        return computeTransform(
            faceRect: m.faceRect,
            eyeCenter: m.eyeCenter,
            interEyeDistance: m.interEyeDistance,
            cutoutSize: CGSize(width: image.width, height: image.height),
            bodyBottomY: m.bodyBottomY
        )
    }

    // MARK: - Actie

    /// Bereken en schrijf het auto-frame-transform voor dit portret; de
    /// geanimeerde overgang komt uit de withAnimation rond de model-writes
    /// (het E06.4-canvas observeert Portrait2).
    @MainActor
    static func apply(to portrait: Portrait2, image: CGImage, undoManager: UndoManager? = nil) async {
        let size = CGSize(width: image.width, height: image.height)
        let before = TransformUndo.snapshot(of: portrait)
        let metrics = await Task.detached(priority: .userInitiated) {
            Self.metrics(for: image)
        }.value
        let transform = computeTransform(
            faceRect: metrics.faceRect,
            eyeCenter: metrics.eyeCenter,
            interEyeDistance: metrics.interEyeDistance,
            cutoutSize: size,
            bodyBottomY: metrics.bodyBottomY
        )
        withAnimation(.spring(duration: 0.45)) {
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
