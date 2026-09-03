import CoreGraphics
import Testing
@testable import Avatar2

@Suite struct BannerCanvasChromeMetricsTests {

    @Test func fitLayoutUsesFullViewportWidthWithoutPadding() {
        let viewport = CGSize(width: 1200, height: 800)
        let canvas = CGSize(width: 1584, height: 396)
        let layout = BannerCanvasChromeMetrics.fitLayout(
            canvasSize: canvas,
            viewport: viewport,
            horizontalPadding: 0
        )
        #expect(layout.drawn.width == BannerCanvasChromeMetrics.maxCardWidth)
        #expect(layout.origin.x == (viewport.width - layout.drawn.width) / 2)
    }
}
