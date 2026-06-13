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
}
