import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Vision

/// Engine A uit pipeline-audit-2.0.md: de minimale Vision-cutout.
///
/// Bewust alléén de onomstreden stages uit de 1.x-pipeline (1–4, 12–13):
/// adaptieve Vision-input → fg-mask + gated person-seg-union → guided
/// filter → clamp → composite, alles in linear-sRGB. De refinement-stages
/// 5–11 (strict matte, hair zone, colour attenuation, edge band,
/// blur-fusion) komen hier niet terug zonder bakeoff-bewijs (E02.2).
public struct VisionCutoutEngine: CutoutEngine {
    public enum Failure: Error, Equatable {
        /// Vision vond geen voorgrond-instantie (bv. leeg of vlak beeld).
        case noSubjectFound
        /// Core Image kon het eindresultaat niet renderen.
        case renderFailed
    }

    public let kind: CutoutEngineKind = .vision

    /// On-device en zonder download; de package-floor (macOS 14) is
    /// tegelijk de OS-floor van VNGenerateForegroundInstanceMaskRequest.
    public var isAvailable: Bool {
        get async { true }
    }

    public init() {}

    private static var context: CIContext { EngineRendering.linearContext }

    public func cutout(_ image: CGImage) async throws -> CGImage {
        let original = CIImage(cgImage: image)
        let extent = original.extent

        // Stage 1 — adaptieve Vision-input.
        let visionImage = Self.visionInput(from: image)

        // Stage 2 — gepinde revisions + 16-bit half person-seg, zodat een
        // stille modelwijziging bij een OS-update ons gedrag niet verschuift
        // en de zachte rand niet op 8-bit afkapt.
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        foreground.revision = VNGenerateForegroundInstanceMaskRequestRevision1

        let personSeg = VNGeneratePersonSegmentationRequest()
        personSeg.revision = VNGeneratePersonSegmentationRequestRevision1
        personSeg.qualityLevel = .accurate
        personSeg.outputPixelFormat = kCVPixelFormatType_OneComponent16Half

        let handler = VNImageRequestHandler(cgImage: visionImage, options: [:])
        try handler.perform([foreground, personSeg])

        guard let fgObservation = foreground.results?.first else {
            throw Failure.noSubjectFound
        }
        let fgMaskBuffer = try fgObservation.generateScaledMaskForImage(
            forInstances: fgObservation.allInstances,
            from: handler
        )
        let fgMask = Self.scaled(CIImage(cvPixelBuffer: fgMaskBuffer), to: extent)

        // Stage 3 — person-seg ∪ foreground, gated: haarslierten die het
        // fg-masker afkapt overleven in de person-matte, maar alleen binnen
        // een licht gedilateerde fg-zone zodat false positives elders in het
        // frame niet meeliften.
        var matte = fgMask
        if let personBuffer = personSeg.results?.first?.pixelBuffer {
            let person = Self.scaled(CIImage(cvPixelBuffer: personBuffer), to: extent)
            let gate = fgMask.applyingFilter("CIMorphologyMaximum", parameters: [
                kCIInputRadiusKey: 8.0
            ]).cropped(to: extent)
            let gatedPerson = person.applyingFilter("CIDarkenBlendMode", parameters: [
                kCIInputBackgroundImageKey: gate
            ]).cropped(to: extent)
            // Omgekeerde gate (2026-09-03, Thierry: Figma-avatars op een
            // gekleurde schijf): de subject-lift ziet schijf + persoon als één
            // onderwerp en de schijf bleef staan. De foreground telt daarom
            // alleen mee binnen een ruime zone rond de persoon-matte —
            // haarslierten, schouders en een bril blijven, een decoratieve
            // schijf of kader ver buiten het silhouet niet. Zonder bruikbare
            // persoon-matte (geen persoon gevonden) blijft de subject-lift
            // ongewijzigd leidend.
            let personZone = person.applyingFilter("CIMorphologyMaximum", parameters: [
                kCIInputRadiusKey: Self.personGateRadius(for: extent)
            ]).cropped(to: extent)
            let gatedForeground = fgMask.applyingFilter("CIDarkenBlendMode", parameters: [
                kCIInputBackgroundImageKey: personZone
            ]).cropped(to: extent)
            let foregroundBase = Self.personCoversForeground(person: person, foreground: fgMask, extent: extent)
                ? gatedForeground : fgMask
            matte = foregroundBase.applyingFilter("CILightenBlendMode", parameters: [
                kCIInputBackgroundImageKey: gatedPerson
            ]).cropped(to: extent)
        }

        // Stage 4 — guided filter (He et al. 2010): draagt randstructuur
        // van de foto over op de matte. r=8 dekt enkele haarslierten zonder
        // het silhouet te versmeren; ε=1e-4 volgt guide-randen strak.
        let guided = matte.applyingFilter("CIGuidedFilter", parameters: [
            "inputGuideImage": original,
            kCIInputRadiusKey: 8.0,
            "inputEpsilon": 0.0001
        ]).cropped(to: extent)

        // Clamp — de guided filter kan buiten [0,1] schieten; >1 in de matte
        // vermenigvuldigt de RGB in CIBlendWithMask en overbelicht de cutout.
        let clamped = guided.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ]).cropped(to: extent)

        // Stage 13 — composite over transparant.
        let clearBackground = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: extent)
        let alphaMatte = clamped.applyingFilter("CIMaskToAlpha")
        let composed = original.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clearBackground,
            "inputMaskImage": alphaMatte
        ]).cropped(to: extent)

        let outputColorSpace = EngineRendering.outputColorSpace(for: image)
        guard let result = Self.context.createCGImage(composed, from: extent,
                                                      format: .RGBA8,
                                                      colorSpace: outputColorSpace) else {
            throw Failure.renderFailed
        }
        return result
    }

    // MARK: - Adaptieve input

    /// Doelresolutie (lange zijde) voor Vision. Het instance-mask-netwerk
    /// heeft een vaste interne feature-resolutie: veel kleinere input geeft
    /// een blokkerig opgeschaald masker, veel grotere verspilt wall-time
    /// zonder extra detail. 1500–4096 px is de geobserveerde sweet spot.
    static func visionTargetLongEdge(for longEdge: Int) -> Int {
        switch longEdge {
        case ..<1500: return 2048
        case ..<4097: return longEdge
        default:      return 4096
        }
    }

    /// Herschaalt naar de doelresolutie met Lanczos in linear licht. De
    /// maskers worden aan het eind altijd naar de **originele** extent
    /// geschaald, dus callers hoeven niets met deze schaal te doen.
    private static func visionInput(from image: CGImage) -> CGImage {
        let longEdge = max(image.width, image.height)
        let target = visionTargetLongEdge(for: longEdge)
        if target == longEdge { return image }

        let scale = CGFloat(target) / CGFloat(longEdge)
        let outRect = CGRect(x: 0, y: 0,
                             width: Int(round(CGFloat(image.width) * scale)),
                             height: Int(round(CGFloat(image.height) * scale)))
        let resized = CIImage(cgImage: image).applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0
        ])
        let colorSpace = EngineRendering.outputColorSpace(for: image)
        // Bij renderfalen liever Vision op de originele resolutie dan de
        // hele import afbreken.
        guard let cg = context.createCGImage(resized, from: outRect,
                                             format: .RGBA8,
                                             colorSpace: colorSpace) else {
            return image
        }
        return cg
    }

    /// Zone rond de persoon-matte waarbinnen de subject-lift nog meetelt:
    /// ~2,5% van de langste zijde (800 px → 20 px), minimaal 12 px.
    static func personGateRadius(for extent: CGRect) -> Double {
        max(12, 0.025 * Double(max(extent.width, extent.height)))
    }

    /// De persoon-matte dekt minstens ~30% van de gelifte foreground — dan
    /// is de foreground echt "persoon + iets" en mag de rest (schijf, kader)
    /// weg. Dekt de persoon-matte de foreground nauwelijks (geen persoon
    /// herkend, synthetisch beeld), dan blijft de subject-lift leidend.
    static func personCoversForeground(person: CIImage, foreground: CIImage, extent: CGRect) -> Bool {
        let overlap = person.applyingFilter("CIDarkenBlendMode", parameters: [
            kCIInputBackgroundImageKey: foreground
        ]).cropped(to: extent)
        let fgMean = areaMean(foreground, extent: extent)
        guard fgMean > 0.001 else { return false }
        return areaMean(overlap, extent: extent) / fgMean >= 0.3
    }

    private static func areaMean(_ mask: CIImage, extent: CGRect) -> Float {
        let avg = mask.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(avg, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil)
        return pixel[0]
    }

    private static func scaled(_ mask: CIImage, to extent: CGRect) -> CIImage {
        EngineRendering.scaled(mask, to: extent)
    }
}
