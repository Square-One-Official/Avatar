// Persoon-gate voor cutout-mattes (2026-09-03, Thierry: Figma-avatars op een
// gekleurde schijf). Zowel Apple's subject-lift als het ORMBG-matting-model
// zien "schijf + persoon" als één onderwerp, waardoor een decoratieve schijf
// of kader achter de persoon blijft staan. De gate beperkt de matte tot een
// ruime zone rond Vision's persoon-matte — haarslierten, schouders en een
// bril blijven, een schijf ver buiten het silhouet niet. Alleen actief als
// de persoon-matte een substantieel deel (≥ 30%) van de matte dekt; anders
// (geen persoon herkend, synthetisch beeld) blijft de matte ongewijzigd.

import CoreImage
import ImageIO
import Vision

enum PersonGate {

    /// Vision-persoon-matte (accurate, 16-bit half) geschaald naar `extent`;
    /// nil als Vision niets teruggeeft.
    static func personMask(for image: CGImage, extent: CGRect) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.revision = VNGeneratePersonSegmentationRequestRevision1
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent16Half
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let buffer = request.results?.first?.pixelBuffer else { return nil }
        let person = EngineRendering.scaled(CIImage(cvPixelBuffer: buffer), to: extent)
        return confinedToOpaque(person, source: CIImage(cgImage: image), extent: extent)
    }

    /// Persoon-matte × bron-alpha: een pixel die in de bron transparant is,
    /// kan geen persoon zijn. Vision ziet transparant als zwart en markeert
    /// die vlakken (de hoeken buiten een schijf) soms als persoon, waardoor
    /// de zone tot aan de schijfrand reikt en de anti-aliased randpixels
    /// als dunne boog overblijven.
    static func confinedToOpaque(_ person: CIImage, source: CIImage, extent: CGRect) -> CIImage {
        let alphaAsGray = source.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: extent)
        return person.applyingFilter("CIMultiplyBlendMode", parameters: [
            kCIInputBackgroundImageKey: alphaAsGray
        ]).cropped(to: extent)
    }

    /// Zonebreedte rond de persoon-matte. `.wide` (~2,5% van de lange zijde)
    /// voor een matte die zelf al strak is (Apple's subject-lift: de zone
    /// beslist alleen over losstaande objecten). `.tight` (~0,4%) voor een
    /// matte die een schijf/kader vlak ómm de persoon volledig meeneemt
    /// (ORMBG): elke pixel zone laat daar een gekleurde rand staan, dus zo
    /// smal als de haarrand toelaat (~3 px op 800 px).
    enum Zone {
        case wide, tight

        func radius(for extent: CGRect) -> Double {
            let longEdge = Double(max(extent.width, extent.height))
            switch self {
            case .wide: return max(12, 0.025 * longEdge)
            case .tight: return max(2, 0.004 * longEdge)
            }
        }
    }

    /// `matte` beperkt tot de zone rond `person` — of ongewijzigd als de
    /// persoon-matte de matte nauwelijks dekt.
    static func apply(matte: CIImage, person: CIImage, extent: CGRect, zone: Zone = .wide) -> CIImage {
        guard personCovers(matte: matte, person: person, extent: extent) else { return matte }
        // Harde drempel vóór het verbreden: Vision's persoon-matte is (opgeschaald
        // uit lage resolutie) zacht en breed aan de rand, waardoor de rand van een
        // schijf naast de schouders anders nét binnen de zone valt en als dunne
        // boog overblijft.
        let hardPerson = person.applyingFilter("CIColorThreshold", parameters: [
            "inputThreshold": 0.5
        ]).cropped(to: extent)
        let zone = hardPerson.applyingFilter("CIMorphologyMaximum", parameters: [
            kCIInputRadiusKey: zone.radius(for: extent)
        ]).cropped(to: extent)
        #if DEBUG
        if let dumpDir = ProcessInfo.processInfo.environment["AVATAR_CUTOUT_PROBE_DUMP"] {
            for (name, img) in [("person", person), ("zone", zone)] {
                if let cg = EngineRendering.linearContext.createCGImage(img, from: extent),
                   let dest = CGImageDestinationCreateWithURL(
                    URL(fileURLWithPath: "\(dumpDir)/gate-\(name).png") as CFURL, "public.png" as CFString, 1, nil
                   ) {
                    CGImageDestinationAddImage(dest, cg, nil); CGImageDestinationFinalize(dest)
                }
            }
            print("PersonGate: matte.extent=\(matte.extent) person.extent=\(person.extent) zone.extent=\(zone.extent)")
        }
        #endif
        return matte.applyingFilter("CIDarkenBlendMode", parameters: [
            kCIInputBackgroundImageKey: zone
        ]).cropped(to: extent)
    }

    /// De persoon-matte dekt minstens ~30% van de matte.
    static func personCovers(matte: CIImage, person: CIImage, extent: CGRect) -> Bool {
        let overlap = person.applyingFilter("CIDarkenBlendMode", parameters: [
            kCIInputBackgroundImageKey: matte
        ]).cropped(to: extent)
        let matteMean = areaMean(matte, extent: extent)
        guard matteMean > 0.001 else { return false }
        let overlapMean = areaMean(overlap, extent: extent)
        #if DEBUG
        if ProcessInfo.processInfo.environment["AVATAR_CUTOUT_PROBE_DEBUG"] != nil {
            print("PersonGate: matte=\(matteMean) person=\(areaMean(person, extent: extent)) overlap=\(overlapMean) ratio=\(overlapMean / matteMean)")
        }
        #endif
        return overlapMean / matteMean >= 0.3
    }

    private static func areaMean(_ mask: CIImage, extent: CGRect) -> Float {
        let avg = mask.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        var pixel = [Float](repeating: 0, count: 4)
        EngineRendering.linearContext.render(
            avg, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf, colorSpace: nil
        )
        return pixel[0]
    }
}
