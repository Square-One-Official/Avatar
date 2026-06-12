import CoreGraphics
import CoreImage
import XCTest
@testable import AvatarKit

/// Vision herkent synthetische beelden niet als persoon of gezicht
/// (geverifieerd met een probe), dus de zone-opbouw en mask-compositie
/// worden hier deterministisch getest met synthetische maskers en een
/// vaste face rect; end-to-end dekt het noPersonFound-pad.
final class ClothesMaskGeneratorTests: XCTestCase {

    /// Leest het rood-kanaal [0,1] op (x, y) — top-left origin — uit een
    /// grayscale CIImage door één pixel te renderen.
    private func value(at x: CGFloat, _ y: CGFloat, in image: CIImage, extent: CGRect) -> Double {
        // CIImage is bottom-left; vlag de y om zodat de asserties in
        // top-left-coördinaten lezen, net als de face rect.
        let rect = CGRect(x: x, y: extent.height - y - 1, width: 1, height: 1)
        var pixel = [UInt8](repeating: 0, count: 4)
        EngineRendering.standardContext.render(
            image, toBitmap: &pixel, rowBytes: 4, bounds: rect,
            format: .RGBA8, colorSpace: nil
        )
        return Double(pixel[0]) / 255.0
    }

    // Fixture-geometrie: 800×1000, gezicht in het bovenste derde.
    private let extent = CGRect(x: 0, y: 0, width: 800, height: 1000)
    private let faceRect = CGRect(x: 320, y: 280, width: 160, height: 200)

    // MARK: - Hoofd/haar-exclusiezone

    func testHeadExclusionZoneCoversFaceAndCrown() {
        let zone = ClothesMaskGenerator.headExclusionZone(faceRect: faceRect, extent: extent)
        // Midden van het gezicht: vol uitgesloten.
        XCTAssertGreaterThan(value(at: 400, 380, in: zone, extent: extent), 0.95)
        // Kruin (boven de face rect): binnen de crown-radial.
        XCTAssertGreaterThan(value(at: 400, 230, in: zone, extent: extent), 0.95)
        // Net onder de kin (beard-radial).
        XCTAssertGreaterThan(value(at: 400, 495, in: zone, extent: extent), 0.9)
    }

    func testHeadExclusionZoneLeavesTorsoFree() {
        let zone = ClothesMaskGenerator.headExclusionZone(faceRect: faceRect, extent: extent)
        // Borsthoogte, ruim onder de zachte falloff (kin 480 + 0.7×faceW=112
        // beard-falloff en 1.4×faceW crown-falloff reiken daar niet).
        XCTAssertLessThan(value(at: 400, 800, in: zone, extent: extent), 0.05)
        // Schouder links.
        XCTAssertLessThan(value(at: 150, 700, in: zone, extent: extent), 0.05)
    }

    // MARK: - Compositie person × (1 − zone)

    private func solidWhite(_ extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
    }

    func testSubtractingZoneRemovesHeadKeepsTorso() {
        let zone = ClothesMaskGenerator.headExclusionZone(faceRect: faceRect, extent: extent)
        // Persoon = volledig wit masker; clothes = wit minus zone.
        let clothes = ClothesMaskGenerator.subtracting(zone: zone,
                                                       from: solidWhite(extent),
                                                       extent: extent)
        XCTAssertLessThan(value(at: 400, 380, in: clothes, extent: extent), 0.05)   // gezicht eruit
        XCTAssertGreaterThan(value(at: 400, 800, in: clothes, extent: extent), 0.95) // torso blijft
    }

    func testSubtractingRespectsPersonMask() {
        // Persoon = zwart masker → kleding blijft overal leeg, ook buiten de zone.
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        let zone = ClothesMaskGenerator.headExclusionZone(faceRect: faceRect, extent: extent)
        let clothes = ClothesMaskGenerator.subtracting(zone: zone, from: black, extent: extent)
        XCTAssertLessThan(value(at: 400, 800, in: clothes, extent: extent), 0.05)
    }

    // MARK: - Face rect-conversie en luminantie

    func testLargestFaceRectIsNilWithoutObservations() {
        XCTAssertNil(ClothesMaskGenerator.largestFaceRect(observations: nil,
                                                          imageSize: extent.size))
        XCTAssertNil(ClothesMaskGenerator.largestFaceRect(observations: [],
                                                          imageSize: extent.size))
    }

    func testMeanLuminance() {
        XCTAssertEqual(ClothesMaskGenerator.meanLuminance(of: solidWhite(extent)), 1.0,
                       accuracy: 0.02)
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        XCTAssertEqual(ClothesMaskGenerator.meanLuminance(of: black), 0.0, accuracy: 0.02)
    }

    // MARK: - End-to-end foutpad

    func testFlatImageThrowsNoPerson() async {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 400, height: 400, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        let flat = ctx.makeImage()!

        do {
            _ = try await ClothesMaskGenerator().mask(for: flat)
            XCTFail("Verwachtte noPersonFound op vlak beeld")
        } catch let failure as ClothesMaskGenerator.Failure {
            XCTAssertEqual(failure, .noPersonFound)
        } catch {
            XCTFail("Onverwachte fout: \(error)")
        }
    }
}
