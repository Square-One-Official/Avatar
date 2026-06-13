import CoreGraphics
import Testing
@testable import Avatar2

/// E05.6: HairEdgeHeuristic — gladde bovenrand is niet rafelig, gekartelde
/// (spikey) bovenrand wél.
struct HairEdgeHeuristicTests {

    private func image(_ draw: (CGContext, Int, Int) -> Void, w: Int = 256, h: Int = 256) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
        draw(ctx, w, h)
        return ctx.makeImage()!
    }

    @Test func smoothBlockIsNotRagged() {
        // Effen rechthoek met een vlakke bovenrand → niet rafelig.
        let img = image { ctx, w, h in
            ctx.fill(CGRect(x: 40, y: 0, width: w - 80, height: h - 60))
        }
        #expect(!HairEdgeHeuristic.isLikelyRagged(cutout: img))
    }

    /// Vierkante-golf bovenrand: brede banden wisselen tussen vol en half
    /// hoog → grote, contigue top-sprongen (zoals een semi-binaire haarmatte).
    private func squareWaveTop(band: Int = 16) -> CGImage {
        image { ctx, w, h in
            var x = 0
            var full = true
            while x < w {
                let height = full ? h - 20 : (h - 20) / 2
                ctx.fill(CGRect(x: x, y: 0, width: band, height: height))
                x += band
                full.toggle()
            }
        }
    }

    @Test func spikyTopIsRagged() {
        let img = squareWaveTop()
        #expect(HairEdgeHeuristic.isLikelyRagged(cutout: img))
    }

    @Test func raggednessOrdering() {
        let smooth = image { ctx, w, h in ctx.fill(CGRect(x: 0, y: 0, width: w, height: h - 60)) }
        let spiky = squareWaveTop()
        #expect(HairEdgeHeuristic.raggedness(of: spiky) > HairEdgeHeuristic.raggedness(of: smooth))
    }
}
