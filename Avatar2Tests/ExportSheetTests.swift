// E47.3 — ExportSheet vorm/maat-combinaties (E19.1/E33). De sheet biedt
// Shape (square/circle/rounded) × Size (512/1024/2048); de daadwerkelijke
// pixels komen uit `PortraitExporter.makePNG(RenderInput…)` — hier toetsen
// we dat elke combinatie de gevraagde maat oplevert en dat de maskers doen
// wat het platform verwacht (transparante hoeken bij circle/rounded, opaak
// bij square-met-achtergrond). Plus de pure grootteschatting van de sheet.

import AppKit
import AvatarKit
import XCTest
@testable import Avatar2

final class ExportSheetTests: XCTestCase {

    // MARK: - Helpers

    /// Klein cutout-PNG: transparante hoeken, opaak blok in het midden —
    /// de vorm van een echte vrijstaande cutout.
    private func cutoutPNG(size: Int = 64) -> Data {
        let bpr = size * 4
        var buf = [UInt8](repeating: 0, count: bpr * size)
        let inset = size / 4
        for y in inset..<(size - inset) {
            for x in inset..<(size - inset) {
                let i = y * bpr + x * 4
                buf[i] = 180; buf[i + 1] = 120; buf[i + 2] = 90; buf[i + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &buf, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        return rep.representation(using: .png, properties: [:])!
    }

    /// RenderInput zoals de sheet 'm bouwt: rauwe cutout + vlakke
    /// achtergrondkleur, geen transform (padded fit), geen blur.
    private func input(backgroundHex: String? = "#00AA44") -> PortraitExporter.RenderInput {
        PortraitExporter.RenderInput(
            cutoutData: cutoutPNG(),
            adjust: .neutral,
            offsetX: 0, offsetY: 0, scale: 0,
            portraitBlur: false,
            effectBackgroundData: nil,
            originalData: nil,
            backgroundImageData: nil,
            backgroundColorHex: backgroundHex,
            useOriginalBackground: false
        )
    }

    private func bitmap(_ data: Data?) throws -> NSBitmapImageRep {
        try XCTUnwrap(data.flatMap { NSBitmapImageRep(data: $0) })
    }

    private func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        rep.colorAt(x: x, y: y)?.alphaComponent ?? -1
    }

    // MARK: - Vorm × maat

    /// Élke vorm/maat-combinatie uit de sheet levert een PNG in exact de
    /// gevraagde pixelmaat (vierkant).
    func testAlleVormMaatCombinatiesLeverenDeGevraagdeMaat() throws {
        let input = input()
        for shape in ExportShape.allCases {
            for side in PortraitExporter.sizeOptions {
                let data = PortraitExporter.makePNG(input, watermark: false, side: side, shape: shape)
                let rep = try bitmap(data)
                XCTAssertEqual(rep.pixelsWide, side, "\(shape)/\(side): breedte")
                XCTAssertEqual(rep.pixelsHigh, side, "\(shape)/\(side): hoogte")
            }
        }
    }

    /// Circle maskeert de hoeken transparant; het middelpunt blijft opaak
    /// (de achtergrondkleur) — precies wat LinkedIn/WhatsApp-avatars nodig hebben.
    func testCircleMaskeertHoekenMaarNietHetMidden() throws {
        let rep = try bitmap(PortraitExporter.makePNG(input(), watermark: false, side: 512, shape: .circle))
        XCTAssertEqual(alpha(rep, 0, 0), 0, "hoek linksboven hoort transparant")
        XCTAssertEqual(alpha(rep, 511, 511), 0, "hoek rechtsonder hoort transparant")
        XCTAssertEqual(alpha(rep, 256, 256), 1, accuracy: 0.01, "midden hoort opaak")
    }

    /// Rounded (Slack/Discord) snijdt alléén de hoeken weg; de randmiddens
    /// blijven opaak (anders was het gewoon een cirkel).
    func testRoundedMaskeertAlleenDeHoeken() throws {
        let rep = try bitmap(PortraitExporter.makePNG(input(), watermark: false, side: 512, shape: .rounded))
        XCTAssertEqual(alpha(rep, 0, 0), 0, "hoek hoort transparant")
        XCTAssertEqual(alpha(rep, 256, 2), 1, accuracy: 0.01, "randmidden boven hoort opaak")
        XCTAssertEqual(alpha(rep, 2, 256), 1, accuracy: 0.01, "randmidden links hoort opaak")
    }

    /// Square met achtergrondkleur = volledig opaak, tot in de hoeken.
    func testSquareMetAchtergrondkleurIsVolledigOpaak() throws {
        let rep = try bitmap(PortraitExporter.makePNG(input(), watermark: false, side: 512, shape: .square))
        XCTAssertEqual(alpha(rep, 0, 0), 1, accuracy: 0.01)
        XCTAssertEqual(alpha(rep, 511, 511), 1, accuracy: 0.01)
    }

    /// Zonder achtergrond levert square een transparante PNG met de cutout
    /// erin (de hoeken blijven leeg — daar zit de dropzone-transparantie).
    func testSquareZonderAchtergrondBlijftTransparantInDeHoeken() throws {
        let rep = try bitmap(PortraitExporter.makePNG(input(backgroundHex: nil), watermark: false, side: 512, shape: .square))
        XCTAssertEqual(rep.pixelsWide, 512)
        XCTAssertEqual(alpha(rep, 0, 0), 0, "geen achtergrond → hoek transparant")
        XCTAssertEqual(alpha(rep, 256, 256), 1, accuracy: 0.01, "onderwerp (padded fit) opaak in het midden")
    }

    // MARK: - Grootteschatting (sheet-caption)

    func testGrootteschattingSchaaltMonotoonMetDeMaat() {
        XCTAssertNil(ExportSheet.estimatedBytes(referenceBytes: nil, side: 512), "zonder referentie geen schatting")
        XCTAssertEqual(ExportSheet.estimatedBytes(referenceBytes: 40_000, side: 256), 40_000, "referentiemaat = referentiegrootte")
        let estimates = PortraitExporter.sizeOptions.compactMap {
            ExportSheet.estimatedBytes(referenceBytes: 40_000, side: $0)
        }
        XCTAssertEqual(estimates.count, PortraitExporter.sizeOptions.count)
        XCTAssertEqual(estimates, estimates.sorted(), "grotere maat → grotere schatting")
        XCTAssertTrue(zip(estimates, estimates.dropFirst()).allSatisfy { $0 < $1 })
    }
}
