import AppKit
import CoreGraphics
import Testing
@testable import Avatar2

/// E55.13 — deterministische sticker-rand. De geometrie is pure math; de
/// render-test bouwt een synthetische cutout (schijf + "romp"-blok) en leest
/// pixels terug: harde witte rand van de verwachte breedte, rondom gesloten,
/// onderwerp intact, romp onder de kin-snede weg.
struct DieCutRendererTests {

    private let size = CGSize(width: 240, height: 240)

    // MARK: - Geometrie

    @Test func borderRadiusFollowsHeadWidthWithinBounds() {
        let head = CGRect(x: 40, y: 20, width: 400, height: 480)
        let r = DieCutRenderer.borderRadius(
            geometry: .init(headRect: head, contentRect: head), imageSize: CGSize(width: 1000, height: 1000)
        )
        #expect(r == (400 * DieCutRenderer.borderFraction).rounded())
        // Ondergrens: een piepklein hoofd krijgt nog steeds een leesbare rand.
        let tiny = DieCutRenderer.borderRadius(
            geometry: .init(headRect: CGRect(x: 0, y: 0, width: 20, height: 20)), imageSize: CGSize(width: 1000, height: 1000)
        )
        #expect(tiny == DieCutRenderer.minBorderPx)
        // Bovengrens: nooit meer dan een fractie van de korte zijde.
        let huge = DieCutRenderer.borderRadius(
            geometry: .init(headRect: CGRect(x: 0, y: 0, width: 5000, height: 5000)), imageSize: CGSize(width: 100, height: 300)
        )
        #expect(huge == (100 * DieCutRenderer.maxBorderFraction).rounded())
    }

    @Test func noFaceMeansNoClip() {
        #expect(DieCutRenderer.headClip(geometry: .init(contentRect: CGRect(x: 0, y: 0, width: 200, height: 240)), imageSize: size) == nil)
    }

    @Test func compliantStickerKeepsItsOwnBottom() {
        // Onderwerp eindigt al net onder de kin → het model hield zich aan HEAD ONLY.
        let g = DieCutRenderer.Geometry(
            chinY: 120, faceHeight: 80,
            headRect: CGRect(x: 60, y: 20, width: 120, height: 100),
            contentRect: CGRect(x: 60, y: 20, width: 120, height: 120)
        )
        #expect(DieCutRenderer.headClip(geometry: g, imageSize: size) == nil)
    }

    @Test func torsoBelowChinGetsRoundedClip() {
        let g = DieCutRenderer.Geometry(
            chinY: 120, faceHeight: 80,
            headRect: CGRect(x: 60, y: 20, width: 120, height: 100),
            contentRect: CGRect(x: 10, y: 20, width: 220, height: 220)
        )
        let clip = try! #require(DieCutRenderer.headClip(geometry: g, imageSize: size))
        // Snede = kin + halsstuk; hoeken = fractie van de gezichtshoogte.
        #expect(clip.rect.maxY == (120 + DieCutRenderer.neckAllowance * 80).rounded())
        #expect(clip.cornerRadius == (DieCutRenderer.bottomCornerFraction * 80).rounded())
        // Gecentreerd op het hoofd, minstens zo breed als het hoofd, boven het beeld uit.
        #expect(clip.rect.midX == 120)
        #expect(clip.rect.width >= 120)
        #expect(clip.rect.minY < 0)
    }

    // MARK: - Render

    /// Schijf (straal 40, midden (120, 90)) met 1px zachte rand + romp-blok
    /// van y=150 tot de onderrand. `paperRing`: crème ring van 10px rondom de
    /// schijf, ín de alpha (= model-randrest na her-isolatie). Premultiplied
    /// RGBA, top-left rijen.
    private func syntheticCutout(withTorso torso: Bool, paperRing: Bool = false) -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let d = hypot(CGFloat(x) - 120, CGFloat(y) - 90)
                let outer: CGFloat = paperRing ? 50 : 40
                var a: CGFloat = 0
                if d <= outer { a = 1 } else if d < outer + 1 { a = outer + 1 - d }
                if torso, y >= 150, x >= 30, x <= 210 { a = 1 }
                let paper = paperRing && d > 40 && d <= outer + 1
                let i = (y * w + x) * 4
                buf[i] = UInt8((paper ? 240 : 220) * a)
                buf[i + 1] = UInt8((paper ? 232 : 40) * a)
                buf[i + 2] = UInt8((paper ? 214 : 40) * a)
                buf[i + 3] = UInt8(255 * a)
            }
        }
        let ctx = CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    private struct Pixels {
        let width: Int, height: Int
        let bytes: [UInt8]
        init(_ image: CGImage) {
            width = image.width; height = image.height
            var buf = [UInt8](repeating: 0, count: width * height * 4)
            let ctx = CGContext(
                data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = buf
        }
        /// (r, g, b, a) op top-left (x, y).
        func at(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
        }
    }

    private let geometry = DieCutRenderer.Geometry(
        chinY: 120, faceHeight: 80,
        headRect: CGRect(x: 70, y: 50, width: 100, height: 70),
        contentRect: CGRect(x: 30, y: 50, width: 180, height: 190)
    )

    @Test func rendersHardWhiteBorderOfExpectedWidthAllAround() throws {
        let out = try #require(DieCutRenderer.render(syntheticCutout(withTorso: false), geometry: geometry))
        #expect(out.width == 240 && out.height == 240)
        let px = Pixels(out)
        let r = Int(DieCutRenderer.borderRadius(geometry: geometry, imageSize: size))
        #expect(r == Int(DieCutRenderer.minBorderPx))

        // Midden blijft het onderwerp (rood, opaak).
        let center = px.at(120, 90)
        #expect(center.a == 255 && center.r > 180 && center.g < 80)

        // Rondom: halverwege de rand wit en opaak; ruim buiten de rand transparant;
        // de overgang is hard (≤ 3 px van vol naar leeg).
        for (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0), (1, -1), (-1, 1)] {
            let n = hypot(CGFloat(dx), CGFloat(dy))
            func p(_ dist: CGFloat) -> (r: Int, g: Int, b: Int, a: Int) {
                px.at(Int((120 + CGFloat(dx) / n * dist).rounded()), Int((90 + CGFloat(dy) / n * dist).rounded()))
            }
            let inBorder = p(40 + CGFloat(r) / 2)
            #expect(inBorder.a == 255 && inBorder.r > 245 && inBorder.g > 245 && inBorder.b > 245, "richting \(dx),\(dy)")
            #expect(p(40 + CGFloat(r) - 2).a > 200, "rand vol op r-2, richting \(dx),\(dy)")
            #expect(p(40 + CGFloat(r) + 3).a < 40, "rand leeg op r+3, richting \(dx),\(dy)")
            #expect(p(40 + CGFloat(r) + 8).a == 0, "richting \(dx),\(dy)")
        }
    }

    @Test func clipsTorsoBelowChinAndClosesTheBottom() throws {
        let out = try #require(DieCutRenderer.render(syntheticCutout(withTorso: true), geometry: geometry))
        let px = Pixels(out)
        let clip = try #require(DieCutRenderer.headClip(geometry: geometry, imageSize: size))
        let r = Int(DieCutRenderer.borderRadius(geometry: geometry, imageSize: size))
        // Onder snede + rand: leeg — de romp is weg.
        let below = Int(clip.rect.maxY) + r + 6
        #expect(px.at(120, below).a == 0)
        #expect(px.at(60, below).a == 0)
        // Net boven de snede, in het midden: witte rand/plaat (romp zat daar rood, de
        // rand loopt er nu onderlangs) — de sticker sluit onderaan.
        let edge = px.at(120, Int(clip.rect.maxY) + r / 2)
        #expect(edge.a == 255 && edge.r > 245 && edge.g > 245)
        // Buiten de U (ver links op romphoogte) is de romp weg.
        #expect(px.at(35, 180).a == 0)
    }

    // Plaatkleur: zonder papierrest wit; mét een crème model-randrest in de
    // matte neemt de plaat die kleur over (één band i.p.v. crème-binnen-wit).
    @Test func plateColorIsWhiteWithoutPaperRemnant() {
        let c = DieCutRenderer.plateColor(of: syntheticCutout(withTorso: false), bandWidth: 12)
        #expect(c == .white)
    }

    @Test func plateColorAdoptsPaperRemnant() throws {
        let c = DieCutRenderer.plateColor(of: syntheticCutout(withTorso: false, paperRing: true), bandWidth: 12)
        #expect(abs(c.red - 240.0 / 255) < 0.03 && abs(c.green - 232.0 / 255) < 0.03 && abs(c.blue - 214.0 / 255) < 0.03)
        // En de gerenderde rand krijgt die kleur.
        let out = try #require(DieCutRenderer.render(syntheticCutout(withTorso: false, paperRing: true), geometry: geometry))
        let px = Pixels(out)
        let r = Int(DieCutRenderer.borderRadius(geometry: geometry, imageSize: size))
        let band = px.at(120, 90 - 50 - r / 2)
        #expect(band.a == 255 && abs(band.r - 240) <= 4 && abs(band.g - 232) <= 4 && abs(band.b - 214) <= 4)
    }

    @Test func withoutTorsoNothingIsClipped() throws {
        let plain = syntheticCutout(withTorso: false)
        let out = try #require(DieCutRenderer.render(plain, geometry: geometry))
        // Zelfde onderwerp-pixels als zonder clip: de schijf blijft heel.
        let px = Pixels(out)
        #expect(px.at(120, 125).a == 255) // onderrand schijf (y = 90 + 35)
    }
}
