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
        return person.applyingFilter("CIMultiplyBlendMode", parameters: [
            kCIInputBackgroundImageKey: TransparentBackgroundFill.alphaAsGray(source, extent: extent)
        ]).cropped(to: extent)
    }

    /// `matte` beperkt tot de zone rond `person` — of ongewijzigd als de
    /// persoon-matte de matte nauwelijks dekt.
    static func apply(matte: CIImage, person: CIImage, extent: CGRect) -> CIImage {
        guard personCovers(matte: matte, person: person, extent: extent) else { return matte }
        let zone = person.applyingFilter("CIMorphologyMaximum", parameters: [
            kCIInputRadiusKey: gateRadius(for: extent)
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

    /// Zone rond de persoon-matte: ~2,5% van de langste zijde (800 px → 20 px),
    /// minimaal 12 px. Ruim genoeg voor haarslierten en schouders; wat verder
    /// weg ligt (losstaand object) valt af. Een schijf vlak om de persoon is
    /// géén zaak van deze gate meer — die verdwijnt al via
    /// TransparentBackgroundFill vóór het matten.
    static func gateRadius(for extent: CGRect) -> Double {
        max(12, 0.025 * Double(max(extent.width, extent.height)))
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
