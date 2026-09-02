import CoreGraphics
import XCTest
@testable import AvatarKit

final class EnhanceTilePreviewTests: XCTestCase {

    /// Kleurverloop zodat split/pixelate/saturatie meetbaar verschillen.
    private func gradientImage(width: Int = 64, height: Int = 64) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for y in 0..<height {
            for x in 0..<width {
                let r = CGFloat(x) / CGFloat(width)
                let g = CGFloat(y) / CGFloat(height)
                ctx.setFillColor(red: r, green: g, blue: 0.55, alpha: 1)
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()!
    }

    private func checker(width: Int, height: Int, cell: Int = 4) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for y in 0..<height {
            for x in 0..<width {
                let on = ((x / cell) + (y / cell)) % 2 == 0
                ctx.setFillColor(red: on ? 1 : 0, green: on ? 1 : 0, blue: on ? 1 : 0, alpha: 1)
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()!
    }

    private func opaqueCircle(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(red: 0.9, green: 0.15, blue: 0.1, alpha: 1)
        let inset = CGFloat(min(width, height)) * 0.22
        ctx.fillEllipse(in: CGRect(
            x: inset, y: inset,
            width: CGFloat(width) - inset * 2,
            height: CGFloat(height) - inset * 2
        ))
        return ctx.makeImage()!
    }

    private func rgba(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var px = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        px.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            ctx?.draw(
                image,
                in: CGRect(x: -CGFloat(x), y: -CGFloat(image.height - 1 - y),
                           width: CGFloat(image.width), height: CGFloat(image.height))
            )
        }
        return (Int(px[0]), Int(px[1]), Int(px[2]), Int(px[3]))
    }

    private func chroma(_ image: CGImage, x: Int, y: Int) -> Int {
        let p = rgba(image, x: x, y: y)
        return max(p.r, p.g, p.b) - min(p.r, p.g, p.b)
    }

    func testDownscaleCapsLongestSide() throws {
        let input = gradientImage(width: 400, height: 300)
        let out = try XCTUnwrap(EnhanceTilePreview.downscale(input))
        XCTAssertLessThanOrEqual(max(out.width, out.height), Int(EnhanceTilePreview.maxDimension))
        XCTAssertEqual(out.width, 256)
        XCTAssertEqual(out.height, 192)
    }

    func testBoostRightHalfIsBlockierThanLeft() throws {
        let input = gradientImage()
        let pixelated = try XCTUnwrap(EnhanceTilePreview.pixellate(input, scale: 14))
        let out = try XCTUnwrap(EnhanceTilePreview.boost(input))
        XCTAssertEqual(out.width, input.width)
        XCTAssertEqual(out.height, input.height)
        // Split: links = bron, rechts = pixelate.
        XCTAssertEqual(rgba(out, x: 8, y: 32).r, rgba(input, x: 8, y: 32).r)
        XCTAssertEqual(rgba(out, x: 56, y: 32).r, rgba(pixelated, x: 56, y: 32).r)
        XCTAssertLessThan(
            uniqueColors(out, xRange: 36..<60, y: 32),
            uniqueColors(out, xRange: 4..<28, y: 32)
        )
    }

    private func uniqueColors(_ image: CGImage, xRange: Range<Int>, y: Int) -> Int {
        var seen = Set<Int>()
        for x in xRange {
            let p = rgba(image, x: x, y: y)
            seen.insert(p.r << 16 | p.g << 8 | p.b)
        }
        return seen.count
    }

    func testColoriseLeftIsLessSaturatedThanRight() throws {
        let input = gradientImage()
        let out = try XCTUnwrap(EnhanceTilePreview.colorise(input))
        let left = chroma(out, x: 10, y: 32)
        let right = chroma(out, x: 54, y: 32)
        XCTAssertLessThan(left, right, "links hoort desaturated: L\(left) R\(right)")
        XCTAssertLessThan(left, 20, "zwart-wit-helft mag nauwelijks chroma hebben: \(left)")
    }

    func testPortraitSubjectStaysSharperThanBackdrop() throws {
        let backdrop = checker(width: 64, height: 64)
        let subject = opaqueCircle(width: 64, height: 64)
        let out = try XCTUnwrap(EnhanceTilePreview.portrait(subject: subject, backdrop: backdrop))
        XCTAssertEqual(out.width, 64)
        // Midden van de cirkel blijft rood (scherp onderwerp).
        let center = rgba(out, x: 32, y: 32)
        XCTAssertGreaterThan(center.r, 160)
        XCTAssertLessThan(center.g, 80)
        // Hoek: geblurde checker — niet puur zwart of wit.
        let corner = rgba(out, x: 2, y: 2)
        XCTAssertGreaterThan(
            min(corner.r, 255 - corner.r), 8,
            "hoek hoort geblurde checker te zijn: \(corner)"
        )
    }

    private func rowContrast(_ image: CGImage, y: Int) -> Int {
        var lo = 255, hi = 0
        for x in 0..<image.width {
            let r = rgba(image, x: x, y: y).r
            lo = min(lo, r); hi = max(hi, r)
        }
        return hi - lo
    }

    func testRenderCachesAndPreservesSizeForSmallInput() throws {
        let input = gradientImage(width: 48, height: 48)
        let a = try XCTUnwrap(EnhanceTilePreview.render(action: .boost, subject: input))
        let b = try XCTUnwrap(EnhanceTilePreview.render(action: .boost, subject: input))
        XCTAssertEqual(a.width, a.height, "head-crop is vierkant")
        XCTAssertEqual(a.width, b.width)
    }

    func testHeadFocusRectPrefersUpperSubject() {
        let w = 64, h = 64
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        // Bitmap-rij 0 = onderkant. Vul de bovenste 20 rijen (visueel het hoofd).
        for y in (h - 20)..<h {
            for x in 16..<48 {
                let i = (y * w + x) * 4
                pixels[i] = 230
                pixels[i + 1] = 40
                pixels[i + 2] = 25
                pixels[i + 3] = 255
            }
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = ctx.makeImage()!
        let rect = EnhanceTilePreview.headFocusRect(in: image)
        XCTAssertLessThan(rect.maxY, 48, "hoofd-crop mag niet tot de lege onderkant: \(rect)")
        XCTAssertGreaterThan(rect.height, 12)
        XCTAssertLessThan(rect.height, CGFloat(h))
    }

    func testRemoveBackgroundChecker_IsVisibleAndNotLime() throws {
        let subject = opaqueCircle(width: 64, height: 64)
        let out = try XCTUnwrap(EnhanceTilePreview.removeBackground(subject))
        // Cel = max(8, 64/10) = 8: (1,1) en (9,1) zijn buurcellen.
        let a = rgba(out, x: 1, y: 1)
        let b = rgba(out, x: 9, y: 1)
        XCTAssertEqual(a.a, 255)
        XCTAssertLessThan(max(a.r, b.r), 90, "hoek hoort stone-achtig te zijn, geen lime: \(a) \(b)")
        XCTAssertGreaterThanOrEqual(
            abs(a.r - b.r), 20,
            "checker moet zichtbaar contrast hebben: \(a) vs \(b)"
        )
        // Subject blijft erbovenop.
        XCTAssertGreaterThan(rgba(out, x: 32, y: 32).r, 160)
    }

    func testStudioLightHasNoCornerFlare() throws {
        let subject = opaqueCircle(width: 64, height: 64)
        let out = try XCTUnwrap(EnhanceTilePreview.studioLight(subject))
        let stoneR = Int(EnhanceTilePreview.stone.r * 255)
        // Rechterbovenhoek (waar de oude flare zat) is niet lichter dan stone.
        let corner = rgba(out, x: 60, y: 3)
        XCTAssertLessThanOrEqual(corner.r, stoneR + 2, "geen flare in de hoek: \(corner)")
        XCTAssertGreaterThan(rgba(out, x: 32, y: 32).r, 120, "onderwerp blijft belicht")
    }

    func testFillBodySolidTopAndStippledBottom() throws {
        let subject = opaqueCircle(width: 80, height: 80)
        let out = try XCTUnwrap(EnhanceTilePreview.fillBody(subject))
        // Boven de breuklijn (38 % van 80 ≈ 30): het rode subject zelf.
        let top = rgba(out, x: 40, y: 22)
        XCTAssertGreaterThan(top.r, 160)
        XCTAssertLessThan(top.g, 80)
        // Onder de breuklijn: geen rood meer, wél stone én lichtere stippel-pixels.
        var reds = 0, lights = 0, stones = 0
        for y in 52..<62 {
            for x in 20..<60 {
                let p = rgba(out, x: x, y: y)
                if p.r > 120 && p.g < 80 { reds += 1 }
                if p.r > 70 { lights += 1 }
                if p.r < 50 { stones += 1 }
            }
        }
        XCTAssertEqual(reds, 0, "onderkant hoort niet solid te zijn")
        XCTAssertGreaterThan(lights, 0, "stippel/contour hoort zichtbaar te zijn")
        XCTAssertGreaterThan(stones, 0, "tussen de stippen stone")
    }

    func testRenderLayersProvidesSubjectWithAlphaAndReveal() throws {
        let subject = opaqueCircle(width: 96, height: 96)
        let layers = try XCTUnwrap(
            EnhanceTilePreview.renderLayers(action: .fillBody, subject: subject)
        )
        XCTAssertNotNil(layers.reveal)
        XCTAssertEqual(layers.base.width, layers.subject.width)
        // Subject-laag houdt alpha (masker); base is over stone gecomposit.
        let cornerSubject = rgba(layers.subject, x: 1, y: 1)
        XCTAssertEqual(cornerSubject.a, 0, "subject-laag hoort transparant te blijven")
        XCTAssertEqual(rgba(layers.base, x: 1, y: 1).a, 255)
        // Synthetische cirkel heeft geen gezicht → geen focus, geen crash.
        XCTAssertNil(layers.focus)
    }

    func testBoostStepsResolveProgressively() throws {
        let input = gradientImage(width: 96, height: 96)
        let layers = try XCTUnwrap(EnhanceTilePreview.renderLayers(action: .boost, subject: input))
        XCTAssertEqual(layers.steps.count, EnhanceTilePreview.boostResolveScales.count)
        // Rechterhelft wordt per stap minder blokkerig: meer unieke kleuren.
        let side = layers.base.width
        let y = side / 2
        let range = (side / 2 + 2)..<(side - 2)
        var previous = uniqueColors(layers.base, xRange: range, y: y)
        for step in layers.steps {
            let count = uniqueColors(step, xRange: range, y: y)
            XCTAssertGreaterThanOrEqual(count, previous, "stap hoort scherper te zijn dan de vorige")
            previous = count
        }
        let sharp = uniqueColors(try XCTUnwrap(layers.reveal), xRange: range, y: y)
        XCTAssertGreaterThan(sharp, uniqueColors(layers.base, xRange: range, y: y))
    }

    func testRetouchPreviewSmoothsWithoutTintOrBlowout() throws {
        // Ruisige rode cirkel: smoothing hoort de ruis te dempen, niet te kleuren.
        let input = noisyCircle(width: 96, height: 96)
        let out = try XCTUnwrap(EnhanceTilePreview.retouchPreview(input))
        XCTAssertEqual(out.width, 96)
        XCTAssertEqual(out.height, 96)
        XCTAssertEqual(rgba(out, x: 1, y: 1).a, 0, "transparante hoek blijft transparant")
        let center = rgba(out, x: 48, y: 48)
        XCTAssertGreaterThan(center.r, 150)
        XCTAssertLessThan(center.g, 110, "geen kleurverschuiving/overbelichting")
        XCTAssertLessThan(
            uniqueColors(out, xRange: 36..<60, y: 48),
            uniqueColors(input, xRange: 36..<60, y: 48),
            "midden hoort gladder (minder ruis) te zijn"
        )
    }

    private func noisyCircle(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        var seed: UInt64 = 7
        let inset = CGFloat(min(width, height)) * 0.22
        let cx = CGFloat(width) / 2, cy = CGFloat(height) / 2, r = CGFloat(width) / 2 - inset
        for y in 0..<height {
            for x in 0..<width {
                let dx = CGFloat(x) + 0.5 - cx, dy = CGFloat(y) + 0.5 - cy
                guard dx * dx + dy * dy <= r * r else { continue }
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                // Huidtextuur: lage-amplitude ruis (geen harde randen).
                let n = CGFloat((seed >> 33) % 100) / 100 * 0.08
                ctx.setFillColor(red: 0.7 + n, green: 0.12 + n * 0.4, blue: 0.1, alpha: 1)
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()!
    }

    func testNormalizeMapsCropToUnitSquare() {
        // Crop 40×20 op (10,30) → vierkant 40 met piece verticaal gecentreerd (offset 10).
        let crop = CGRect(x: 10, y: 30, width: 40, height: 20)
        let face = CGRect(x: 20, y: 35, width: 20, height: 10)
        let n = EnhanceTilePreview.normalize(face, crop: crop, side: 40)
        XCTAssertEqual(n.minX, 0.25, accuracy: 0.001)
        XCTAssertEqual(n.minY, (5 + 10) / 40, accuracy: 0.001)
        XCTAssertEqual(n.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(n.height, 0.25, accuracy: 0.001)
    }

    func testPortraitRestIsSharperThanFull() throws {
        // Grove checker (cel 16): lichte blur houdt de cellen leesbaar,
        // zware blur vlakt ze af → minder contrast op een rij naast het subject.
        let backdrop = checker(width: 64, height: 64, cell: 16)
        let subject = opaqueCircle(width: 64, height: 64)
        let rest = try XCTUnwrap(EnhanceTilePreview.portrait(
            subject: subject, backdrop: backdrop, blurFraction: EnhanceTilePreview.portraitBlurRest))
        let full = try XCTUnwrap(EnhanceTilePreview.portrait(
            subject: subject, backdrop: backdrop, blurFraction: EnhanceTilePreview.portraitBlurFull))
        XCTAssertGreaterThan(rowContrast(rest, y: 4), rowContrast(full, y: 4))
    }
}
