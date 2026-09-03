import CoreGraphics
import Testing
@testable import Avatar2

/// AutoFramer (E06.5): pure transform-math, geport uit v1 AutoAligner.
/// Doelwaarden staan vast (FramingConstants) — deze tests pinnen het
/// gedrag, niet de getallen zelf.
struct AutoFramerTests {

    private let canvas = CGSize(width: 1024, height: 1024)

    @Test func eyeBasedPutsEyesOnStandardEyeline() {
        let eye = CGPoint(x: 500, y: 400)
        let t = AutoFramer.computeTransform(
            faceRect: CGRect(x: 400, y: 300, width: 200, height: 260),
            eyeCenter: eye,
            interEyeDistance: 100,
            cutoutSize: CGSize(width: 1000, height: 1200)
        )
        // Schaal: interoog → 12% van canvashoogte.
        #expect(abs(t.scale - (1024 * 0.12) / 100) < 0.0001)
        // Oogmidden landt op (0.50, 0.37) van het canvas.
        let projectedX = eye.x * t.scale + t.offset.width
        let projectedY = eye.y * t.scale + t.offset.height
        #expect(abs(projectedX - 1024 * 0.50) < 0.001)
        #expect(abs(projectedY - 1024 * 0.37) < 0.001)
    }

    // Sticker-fix: een die-cut-resultaat wordt als vrijstaande vorm gekaderd —
    // alpha-bbox gecentreerd met de standaard ademruimte, géén body-overshoot.
    @Test func freestandingFitCentersContentWithPadding() {
        let content = CGRect(x: 100, y: 50, width: 400, height: 300)
        let t = AutoFramer.freestandingTransform(
            contentRect: content, cutoutSize: CGSize(width: 800, height: 800), canvas: canvas
        )
        #expect(abs(t.scale - (1024 / 400) * FramingConstants.frameFitPadding) < 0.0001)
        let cx = content.midX * t.scale + t.offset.width
        let cy = content.midY * t.scale + t.offset.height
        #expect(abs(cx - 512) < 0.001)
        #expect(abs(cy - 512) < 0.001)
    }

    @Test func freestandingWithoutContentFitsWholeCutout() {
        let size = CGSize(width: 800, height: 1000)
        let t = AutoFramer.freestandingTransform(contentRect: nil, cutoutSize: size, canvas: canvas)
        #expect(t == AutoFramer.fitTransform(cutoutSize: size, canvas: canvas))
    }

    @Test func faceRectFallbackCentersFace() {
        let face = CGRect(x: 100, y: 100, width: 300, height: 400)
        let t = AutoFramer.computeTransform(
            faceRect: face,
            cutoutSize: CGSize(width: 800, height: 1000)
        )
        #expect(abs(t.scale - (1024 * 0.38) / 400) < 0.0001)
        let projectedY = face.midY * t.scale + t.offset.height
        #expect(abs(projectedY - 1024 * 0.42) < 0.001)
    }

    @Test func bodyOvershootBoostsScale() {
        // Korte romp: bodyBottom dichtbij de ogen → minimum-scale wint.
        let withBody = AutoFramer.computeTransform(
            faceRect: CGRect(x: 0, y: 0, width: 200, height: 200),
            eyeCenter: CGPoint(x: 100, y: 100),
            interEyeDistance: 60,
            cutoutSize: CGSize(width: 400, height: 300),
            bodyBottomY: 220
        )
        let withoutBody = AutoFramer.computeTransform(
            faceRect: CGRect(x: 0, y: 0, width: 200, height: 200),
            eyeCenter: CGPoint(x: 100, y: 100),
            interEyeDistance: 60,
            cutoutSize: CGSize(width: 400, height: 300)
        )
        #expect(withBody.scale > withoutBody.scale)
        // Romp eindigt voorbij de canvasonderkant (+3% overshoot).
        let bottom = 220 * withBody.scale + withBody.offset.height
        #expect(bottom >= 1024 * 1.029)
    }

    @Test func noFaceFallsBackToPaddedFit() {
        let t = AutoFramer.computeTransform(
            faceRect: nil,
            cutoutSize: CGSize(width: 2048, height: 1024)
        )
        #expect(abs(t.scale - (1024.0 / 2048.0) * 0.85) < 0.0001)
        // Gecentreerd.
        #expect(abs((t.offset.width * 2 + 2048 * t.scale) - 1024) < 0.001)
    }

    // MARK: resolvedTransform — gedeelde bron voor cutout + Original-achtergrondlaag

    @Test func resolvedTransformKeepsPersistedWhenScalePositive() {
        let r = AutoFramer.resolvedTransform(
            offsetX: 120, offsetY: -30, scale: 0.7,
            cutoutSize: CGSize(width: 800, height: 1000)
        )
        #expect(r.offsetX == 120)
        #expect(r.offsetY == -30)
        #expect(r.scale == 0.7)
    }

    @Test func resolvedTransformFallsBackToPaddedFitWhenScaleZero() {
        let size = CGSize(width: 2048, height: 1024)
        // scale == 0 → de meegegeven offsets worden genegeerd; de gedeelde
        // padded-fit-fallback (zelfde als het cutout) wint.
        let r = AutoFramer.resolvedTransform(
            offsetX: 999, offsetY: 999, scale: 0, cutoutSize: size
        )
        let fit = AutoFramer.fitTransform(cutoutSize: size)
        #expect(abs(r.scale - Double(fit.scale)) < 0.0001)
        #expect(abs(r.offsetX - Double(fit.offset.width)) < 0.0001)
        #expect(abs(r.offsetY - Double(fit.offset.height)) < 0.0001)
        #expect(r.offsetX != 999)
    }

    @Test func sharedFramingKeepsEqualIPDAndFillsBottom() {
        // Close-up (grote IPD, korte romp) vs medium shot (kleine IPD, lange romp).
        let closeUp = AutoFramer.FramingSubject(
            faceRect: CGRect(x: 0, y: 0, width: 240, height: 240),
            eyeCenter: CGPoint(x: 120, y: 100),
            interEyeDistance: 120,
            bodyBottomY: 220,
            cutoutSize: CGSize(width: 400, height: 300)
        )
        // Frontale verhouding IPD/face-box ≈ 0.40 (boven de IED-ondergrens).
        let medium = AutoFramer.FramingSubject(
            faceRect: CGRect(x: 0, y: 0, width: 150, height: 150),
            eyeCenter: CGPoint(x: 100, y: 100),
            interEyeDistance: 60,
            bodyBottomY: 800,
            cutoutSize: CGSize(width: 400, height: 900)
        )
        let transforms = AutoFramer.computeSharedTransforms([closeUp, medium])
        #expect(transforms.count == 2)

        let closeIPD = closeUp.interEyeDistance! * transforms[0].scale
        let mediumIPD = medium.interEyeDistance! * transforms[1].scale
        #expect(abs(closeIPD - mediumIPD) < 0.001)

        let requiredBottom = 1024 * (1.0 + FramingConstants.bodyOvershoot)
        let closeBottom = closeUp.bodyBottomY * transforms[0].scale + transforms[0].offset.height
        let mediumBottom = medium.bodyBottomY * transforms[1].scale + transforms[1].offset.height
        #expect(closeBottom >= requiredBottom - 0.001)
        #expect(mediumBottom >= requiredBottom - 0.001)

        let closeEyeY = closeUp.eyeCenter!.y * transforms[0].scale + transforms[0].offset.height
        let mediumEyeY = medium.eyeCenter!.y * transforms[1].scale + transforms[1].offset.height
        #expect(abs(closeEyeY - 1024 * FramingConstants.targetEyeCenterY) < 0.001)
        #expect(abs(mediumEyeY - 1024 * FramingConstants.targetEyeCenterY) < 0.001)
    }

    // MARK: Gedraaid hoofd (driekwart-profiel)

    // Bug 2026-09-03: bij 33° yaw meet Vision een 2D-IPD van ~0.33× de
    // face-box-hoogte i.p.v. ~0.40 frontaal; puur eye-based werd zo'n portret
    // 25% verder ingezoomd dan de frontale rest van de set. De boxhoogte
    // (draai-onafhankelijk) begrenst de schaal.
    @Test func turnedHeadUsesFaceBoxFloorForScale() {
        let face = CGRect(x: 326, y: 147, width: 263, height: 263)
        let eye = CGPoint(x: 469, y: 218)
        let t = AutoFramer.computeTransform(
            faceRect: face,
            eyeCenter: eye,
            interEyeDistance: 87.6,
            cutoutSize: CGSize(width: 794, height: 730)
        )
        let floorIED = face.height * FramingConstants.minInterEyeToFaceHeight
        #expect(floorIED > 87.6)
        #expect(abs(t.scale - (1024 * FramingConstants.targetInterEyeRatio) / floorIED) < 0.0001)
        // Ooglijn-anker blijft de echte oogpositie.
        let projectedX = eye.x * t.scale + t.offset.width
        let projectedY = eye.y * t.scale + t.offset.height
        #expect(abs(projectedX - 1024 * FramingConstants.targetEyeCenterX) < 0.001)
        #expect(abs(projectedY - 1024 * FramingConstants.targetEyeCenterY) < 0.001)
    }

    @Test func frontalHeadKeepsMeasuredIPD() {
        // Liam-achtig: IPD 110 op een box van 278 (0.397) → boven de grens.
        let face = CGRect(x: 183, y: 149, width: 278, height: 278)
        let t = AutoFramer.computeTransform(
            faceRect: face,
            eyeCenter: CGPoint(x: 316, y: 225),
            interEyeDistance: 110.3,
            cutoutSize: CGSize(width: 640, height: 640)
        )
        #expect(abs(t.scale - (1024 * FramingConstants.targetInterEyeRatio) / 110.3) < 0.0001)
    }

    @Test func sharedFramingGivesTurnedHeadSameHeadSizeAsFrontal() {
        // Echte Acme-metingen: Liam (frontaal) + Rhianna (33° yaw).
        let liam = AutoFramer.FramingSubject(
            faceRect: CGRect(x: 183, y: 149, width: 278, height: 278),
            eyeCenter: CGPoint(x: 316, y: 225),
            interEyeDistance: 110.3,
            bodyBottomY: 640,
            cutoutSize: CGSize(width: 640, height: 640)
        )
        let rhianna = AutoFramer.FramingSubject(
            faceRect: CGRect(x: 326, y: 147, width: 263, height: 263),
            eyeCenter: CGPoint(x: 469, y: 218),
            interEyeDistance: 87.6,
            bodyBottomY: 730,
            cutoutSize: CGSize(width: 794, height: 730)
        )
        let transforms = AutoFramer.computeSharedTransforms([liam, rhianna])
        let liamHead = liam.faceRect!.height * transforms[0].scale
        let rhiannaHead = rhianna.faceRect!.height * transforms[1].scale
        // Hoofden binnen 6% van elkaar (was 19% te groot vóór de ondergrens).
        #expect(abs(rhiannaHead - liamHead) / liamHead < 0.06)
        #expect(transforms[1].scale < transforms[0].scale * 1.15)
    }

    @Test func doublingCutoutHalvesScaleAndKeepsEyeProjection() {
        let face = CGRect(x: 400, y: 300, width: 200, height: 260)
        let eye = CGPoint(x: 500, y: 400)
        let t1 = AutoFramer.computeTransform(
            faceRect: face,
            eyeCenter: eye,
            interEyeDistance: 100,
            cutoutSize: CGSize(width: 1000, height: 1200)
        )
        let t2 = AutoFramer.computeTransform(
            faceRect: CGRect(x: 800, y: 600, width: 400, height: 520),
            eyeCenter: CGPoint(x: 1000, y: 800),
            interEyeDistance: 200,
            cutoutSize: CGSize(width: 2000, height: 2400)
        )
        #expect(abs(t2.scale - t1.scale / 2) < 0.0001)
        let p1 = CGPoint(x: eye.x * t1.scale + t1.offset.width, y: eye.y * t1.scale + t1.offset.height)
        let p2 = CGPoint(x: 1000 * t2.scale + t2.offset.width, y: 800 * t2.scale + t2.offset.height)
        #expect(abs(p1.x - p2.x) < 0.001)
        #expect(abs(p1.y - p2.y) < 0.001)
        #expect(p2.x > 0 && p2.x < 1024)
        #expect(p2.y > 0 && p2.y < 1024)
    }

    // MARK: Content-aware fit (Hairy / Windy halo)

    @Test func noFaceCentersOffCenterOpaqueSubject() {
        // Vision vindt geen gezicht (haar-sculptuur). De cutout is groter
        // dan het onderwerp, dat linksboven in het PNG zit.
        let content = CGRect(x: 40, y: 30, width: 220, height: 280)
        let t = AutoFramer.computeTransform(
            faceRect: nil,
            cutoutSize: CGSize(width: 1000, height: 1000),
            contentRect: content
        )
        let midX = content.midX * t.scale + t.offset.width
        let midY = content.midY * t.scale + t.offset.height
        #expect(abs(midX - 512) < 0.001)
        #expect(abs(midY - 512) < 0.001)
        let top = content.minY * t.scale + t.offset.height
        let bottom = content.maxY * t.scale + t.offset.height
        #expect(top >= 0)
        #expect(bottom <= 1024)
        // Zou het volledige PNG centreren, dan landt het onderwerp níet in het midden.
        let imageFit = AutoFramer.fitTransform(cutoutSize: CGSize(width: 1000, height: 1000))
        let uncenteredX = content.midX * imageFit.scale + imageFit.offset.width
        #expect(abs(uncenteredX - 512) > 50)
    }

    @Test func hairyHaloFitsAndCentersInsteadOfClipping() {
        // Gezicht blijft detecteerbaar, maar Hairy vult een halo rond het hoofd.
        // Eye-based kader zou de halo boven/opzij afknippen.
        let face = CGRect(x: 400, y: 300, width: 200, height: 260)
        let eye = CGPoint(x: 500, y: 400)
        let halo = CGRect(x: 40, y: 10, width: 920, height: 1100)
        let t = AutoFramer.computeTransform(
            faceRect: face,
            eyeCenter: eye,
            interEyeDistance: 100,
            cutoutSize: CGSize(width: 1000, height: 1200),
            bodyBottomY: 1110,
            contentRect: halo
        )
        let eyeOnly = AutoFramer.computeTransform(
            faceRect: face,
            eyeCenter: eye,
            interEyeDistance: 100,
            cutoutSize: CGSize(width: 1000, height: 1200),
            bodyBottomY: 1110
        )
        #expect(t.scale < eyeOnly.scale)
        let top = halo.minY * t.scale + t.offset.height
        let left = halo.minX * t.scale + t.offset.width
        let right = halo.maxX * t.scale + t.offset.width
        #expect(top >= -0.001)
        #expect(left >= -0.001)
        #expect(right <= 1024.001)
        let midX = halo.midX * t.scale + t.offset.width
        let midY = halo.midY * t.scale + t.offset.height
        #expect(abs(midX - 512) < 0.5)
        #expect(abs(midY - 512) < 0.5)
    }

    @Test func normalBodyContentKeepsEyeFraming() {
        // Schouders + romp onder het gezicht, beetje haar erboven: géén halo.
        let face = CGRect(x: 400, y: 300, width: 200, height: 260)
        let eye = CGPoint(x: 500, y: 400)
        let body = CGRect(x: 320, y: 270, width: 360, height: 800)
        let t = AutoFramer.computeTransform(
            faceRect: face,
            eyeCenter: eye,
            interEyeDistance: 100,
            cutoutSize: CGSize(width: 1000, height: 1200),
            bodyBottomY: 1070,
            contentRect: body
        )
        let eyeBased = AutoFramer.computeTransform(
            faceRect: face,
            eyeCenter: eye,
            interEyeDistance: 100,
            cutoutSize: CGSize(width: 1000, height: 1200),
            bodyBottomY: 1070
        )
        #expect(abs(t.scale - eyeBased.scale) < 0.0001)
        #expect(abs(t.offset.width - eyeBased.offset.width) < 0.0001)
        #expect(abs(t.offset.height - eyeBased.offset.height) < 0.0001)
    }

    @Test func realShouldersAndHairKeepEyeFraming() {
        // Regressie (screenshot 2026-09-02): gewoon portret, schouders ~3×
        // de Vision-face-box breed en haar ~0.45× de boxhoogte erboven.
        // Dat is géén halo — de ooglijn + body-overshoot moeten blijven,
        // ook al steken de schouders onder body-overshoot buiten het canvas.
        let face = CGRect(x: 400, y: 300, width: 200, height: 260)
        let eye = CGPoint(x: 500, y: 400)
        let body = CGRect(x: 180, y: 185, width: 640, height: 815)
        let head = CGRect(x: 330, y: 185, width: 340, height: 375)
        let t = AutoFramer.computeTransform(
            faceRect: face,
            eyeCenter: eye,
            interEyeDistance: 100,
            cutoutSize: CGSize(width: 1000, height: 1000),
            bodyBottomY: 1000,
            contentRect: body,
            headContentRect: head
        )
        let eyeBased = AutoFramer.computeTransform(
            faceRect: face,
            eyeCenter: eye,
            interEyeDistance: 100,
            cutoutSize: CGSize(width: 1000, height: 1000),
            bodyBottomY: 1000
        )
        #expect(abs(t.scale - eyeBased.scale) < 0.0001)
        #expect(abs(t.offset.width - eyeBased.offset.width) < 0.0001)
        #expect(abs(t.offset.height - eyeBased.offset.height) < 0.0001)
        // Ooglijn + romp voorbij de onderkant, geen lege band onderin.
        let eyeY = eye.y * t.scale + t.offset.height
        let bottom = body.maxY * t.scale + t.offset.height
        #expect(abs(eyeY - 1024 * 0.37) < 0.001)
        #expect(bottom >= 1024)
    }

    @Test func slightHairOverflowKeepsEyeFraming() {
        // Haartop valt een paar px boven het canvas: v1 accepteerde dat,
        // de content-fit mag hier niet op aanslaan.
        let face = CGRect(x: 400, y: 300, width: 200, height: 260)
        let eye = CGPoint(x: 500, y: 400)
        let head = CGRect(x: 330, y: 100, width: 340, height: 460)
        let body = CGRect(x: 180, y: 100, width: 640, height: 900)
        let t = AutoFramer.computeTransform(
            faceRect: face,
            eyeCenter: eye,
            interEyeDistance: 100,
            cutoutSize: CGSize(width: 1000, height: 1000),
            bodyBottomY: 1000,
            contentRect: body,
            headContentRect: head
        )
        let eyeBased = AutoFramer.computeTransform(
            faceRect: face,
            eyeCenter: eye,
            interEyeDistance: 100,
            cutoutSize: CGSize(width: 1000, height: 1000),
            bodyBottomY: 1000
        )
        #expect(abs(t.scale - eyeBased.scale) < 0.0001)
        #expect(abs(t.offset.height - eyeBased.offset.height) < 0.0001)
    }

    @Test func hairyHaloOnHeadBandStillLeadsFraming() {
        // Halo gemeten op de hoofdband (niet via de schouders) → content-fit.
        let face = CGRect(x: 400, y: 300, width: 200, height: 260)
        let eye = CGPoint(x: 500, y: 400)
        let head = CGRect(x: 60, y: 10, width: 880, height: 550)
        let body = CGRect(x: 60, y: 10, width: 880, height: 1100)
        let t = AutoFramer.computeTransform(
            faceRect: face,
            eyeCenter: eye,
            interEyeDistance: 100,
            cutoutSize: CGSize(width: 1000, height: 1200),
            bodyBottomY: 1110,
            contentRect: body,
            headContentRect: head
        )
        let top = body.minY * t.scale + t.offset.height
        let left = body.minX * t.scale + t.offset.width
        let right = body.maxX * t.scale + t.offset.width
        #expect(top >= -0.001)
        #expect(left >= -0.001)
        #expect(right <= 1024.001)
    }

    @Test func headContentRectStopsAtChin() {
        // Smal hoofd bovenaan, brede schouders eronder: de hoofdband mag de
        // schouders niet meenemen.
        let cg = twoBlobImage(
            width: 128, height: 128,
            head: CGRect(x: 48, y: 8, width: 32, height: 40),
            body: CGRect(x: 8, y: 48, width: 112, height: 72)
        )
        let full = AutoFramer.contentRectFromAlpha(of: cg)
        let head = AutoFramer.headContentRectFromAlpha(of: cg, chinY: 48)
        #expect(abs((full?.width ?? 0) - 112) <= 2)
        #expect(head != nil)
        #expect(abs((head?.minX ?? 0) - 48) <= 2)
        #expect(abs((head?.width ?? 0) - 32) <= 2)
        #expect((head?.maxY ?? 0) <= 48)
    }

    private func twoBlobImage(width: Int, height: Int, head: CGRect, body: CGRect) -> CGImage {
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        for rect in [head, body] {
            let x0 = Int(rect.minX), y0 = Int(rect.minY)
            let x1 = Int(rect.maxX), y1 = Int(rect.maxY)
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let i = y * bpr + x * 4
                    buf[i] = 255; buf[i + 1] = 200; buf[i + 2] = 180; buf[i + 3] = 255
                }
            }
        }
        let ctx = CGContext(
            data: &buf, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    @Test func contentRectFromAlphaFindsOpaqueBlob() {
        let cg = opaqueRectImage(width: 80, height: 80, rect: CGRect(x: 12, y: 18, width: 20, height: 30))
        let rect = AutoFramer.contentRectFromAlpha(of: cg)
        #expect(rect != nil)
        #expect(abs((rect?.minX ?? 0) - 12) <= 1)
        #expect(abs((rect?.minY ?? 0) - 18) <= 1)
        #expect(abs((rect?.width ?? 0) - 20) <= 1)
        #expect(abs((rect?.height ?? 0) - 30) <= 1)
    }

    private func opaqueRectImage(width: Int, height: Int, rect: CGRect) -> CGImage {
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        let x0 = Int(rect.minX), y0 = Int(rect.minY)
        let x1 = Int(rect.maxX), y1 = Int(rect.maxY)
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = y * bpr + x * 4
                buf[i] = 255; buf[i + 1] = 200; buf[i + 2] = 180; buf[i + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &buf, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bpr, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }
}
