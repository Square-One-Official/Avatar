import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision

/// Kleding-masker voor de Clothes-flow (E10): person-segmentatie minus een
/// hoofd/haar-exclusiezone uit de face rect. Wit = kleding (inpaint-gebied
/// voor FLUX Fill), zwart = niet aanraken.
///
/// De zone-geometrie is bewust dezelfde als v1's bewezen crown/beard-
/// ellipsen. Bekende beperkingen (achterhoofd zonder gezicht, hoeden,
/// extreem zijprofiel) zijn geaccepteerd voor het macOS 26-pad; de
/// correctie-laag uit pipeline-audit-2.0.md (tap-to-segment, macOS 27)
/// vervangt deze heuristiek waar hij faalt.
///
/// Er zit bewust géén refinement op het masker: de consument (Clothes-
/// paneel, E10.2) bepaalt zelf dilate/feather richting de inpaint-backend.
public struct ClothesMaskGenerator: Sendable {
    public enum Failure: Error, Equatable {
        /// Person-segmentatie vond geen persoon (lege of bijna-lege matte).
        case noPersonFound
        /// Geen gezicht gedetecteerd — zonder face rect is er geen
        /// betrouwbare hoofd/haar-zone om uit te sluiten.
        case noFaceFound
        /// Core Image kon het eindresultaat niet renderen.
        case renderFailed
    }

    public init() {}

    /// Grayscale kleding-masker op bron-resolutie (wit = kleding).
    public func mask(for image: CGImage) async throws -> CGImage {
        let extent = CIImage(cgImage: image).extent

        // Person-seg + face rect — gepinde revisions, zelfde verzekering
        // tegen stille OS-gedragswijziging als in VisionCutoutEngine.
        let personSeg = VNGeneratePersonSegmentationRequest()
        personSeg.revision = VNGeneratePersonSegmentationRequestRevision1
        personSeg.qualityLevel = .accurate
        personSeg.outputPixelFormat = kCVPixelFormatType_OneComponent16Half

        let faceReq = VNDetectFaceRectanglesRequest()
        faceReq.revision = VNDetectFaceRectanglesRequestRevision3

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([personSeg, faceReq])

        guard let personBuffer = personSeg.results?.first?.pixelBuffer else {
            throw Failure.noPersonFound
        }
        let personRaw = CIImage(cvPixelBuffer: personBuffer)
        // Person-seg geeft op niet-personen een geldige maar (vrijwel) lege
        // matte terug — een gemiddelde onder ~1/255 betekent: geen persoon.
        guard Self.meanLuminance(of: personRaw) > (1.0 / 255.0) else {
            throw Failure.noPersonFound
        }
        let person = EngineRendering.scaled(personRaw, to: extent)

        guard let faceRect = Self.largestFaceRect(observations: faceReq.results,
                                                  imageSize: extent.size) else {
            throw Failure.noFaceFound
        }

        let zone = Self.headExclusionZone(faceRect: faceRect, extent: extent)
        let clothes = Self.subtracting(zone: zone, from: person, extent: extent)

        guard let result = EngineRendering.linearContext.createCGImage(
            clothes, from: extent, format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ) else {
            throw Failure.renderFailed
        }
        return result
    }

    // MARK: - Bouwstenen (intern, deterministisch getest — Vision herkent
    // synthetische testbeelden niet als persoon/gezicht)

    /// Zachte hoofd/haar-zone: crown- en beard-radialen met de v1-getallen,
    /// plus een gezichts-ovaal zodat ook het gezicht zelf buiten het
    /// kleding-masker valt. `faceRect` in pixelcoördinaten, origin TOP-LEFT.
    static func headExclusionZone(faceRect: CGRect, extent: CGRect) -> CIImage {
        let imageH = extent.height
        let faceCenterX = faceRect.midX
        let faceTopY = imageH - faceRect.minY      // CI-coördinaten (bottom-left)
        let faceBottomY = imageH - faceRect.maxY
        let faceCenterY = imageH - faceRect.midY
        let faceW = faceRect.width
        let faceH = faceRect.height

        func radial(center: CIVector, hard: CGFloat, soft: CGFloat) -> CIImage {
            CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": center,
                "inputRadius0": hard,
                "inputRadius1": soft,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            ])!.outputImage!.cropped(to: extent)
        }

        // Crown — iets boven het voorhoofd; breed genoeg voor slaaphaar.
        let crown = radial(center: CIVector(x: faceCenterX, y: faceTopY + faceH * 0.2),
                           hard: faceW * 0.6, soft: faceW * 1.4)
        // Beard — net onder de kin, vangt baard/stoppels over de halslijn.
        let beard = radial(center: CIVector(x: faceCenterX, y: faceBottomY - faceH * 0.1),
                           hard: faceW * 0.3, soft: faceW * 0.7)
        // Gezicht — dekt de face rect zelf af.
        let face = radial(center: CIVector(x: faceCenterX, y: faceCenterY),
                          hard: faceH * 0.6, soft: faceH * 0.9)

        // Union via lighten = max per pixel.
        return crown.applyingFilter("CILightenBlendMode", parameters: [
            kCIInputBackgroundImageKey: beard
        ]).applyingFilter("CILightenBlendMode", parameters: [
            kCIInputBackgroundImageKey: face
        ]).cropped(to: extent)
    }

    /// clothes = person × (1 − zone), geklemd op [0,1].
    static func subtracting(zone: CIImage, from person: CIImage, extent: CGRect) -> CIImage {
        let inverted = zone.applyingFilter("CIColorInvert")
        return person.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: inverted
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ]).cropped(to: extent)
    }

    /// Grootste gezicht in pixelcoördinaten, origin TOP-LEFT (Vision geeft
    /// genormaliseerd bottom-left terug).
    static func largestFaceRect(observations: [VNFaceObservation]?,
                                imageSize: CGSize) -> CGRect? {
        guard let observations, !observations.isEmpty else { return nil }
        let largest = observations.max {
            $0.boundingBox.width * $0.boundingBox.height
                < $1.boundingBox.width * $1.boundingBox.height
        }!
        let bb = largest.boundingBox
        return CGRect(
            x: bb.minX * imageSize.width,
            y: (1 - bb.maxY) * imageSize.height,
            width: bb.width * imageSize.width,
            height: bb.height * imageSize.height
        )
    }

    /// Gemiddelde luminantie [0,1] via CIAreaAverage.
    static func meanLuminance(of image: CIImage) -> Double {
        let average = image.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: image.extent)
        ])
        var pixel = [UInt8](repeating: 0, count: 4)
        EngineRendering.standardContext.render(
            average, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil
        )
        return Double(pixel[0]) / 255.0
    }
}
