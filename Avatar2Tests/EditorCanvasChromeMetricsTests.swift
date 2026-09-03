import CoreGraphics
import Testing
@testable import Avatar2

@Suite struct EditorCanvasChromeMetricsTests {

    @Test func coverLayoutFillsWideViewport() {
        let layout = EditorCanvasChromeMetrics.coverLayout(viewport: CGSize(width: 900, height: 700))
        #expect(layout.cardSide == 900)
        #expect(layout.origin == CGPoint(x: 0, y: -100))
        #expect(layout.cardCenter == CGPoint(x: 450, y: 350))
    }

    @Test func coverLayoutFillsTallViewport() {
        let layout = EditorCanvasChromeMetrics.coverLayout(viewport: CGSize(width: 600, height: 800))
        #expect(layout.cardSide == 800)
        #expect(layout.origin == CGPoint(x: -100, y: 0))
    }

    @Test func selectionRingIsCircleWhenFrameIsCircle() {
        #expect(
            EditorCanvasChromeMetrics.selectionRingCornerRadius(
                isCircle: true,
                cameraScale: 1.5,
                cardCornerRadius: 24
            ) == nil
        )
    }

    @Test func selectionRingScalesRoundedRectWithCamera() {
        #expect(
            EditorCanvasChromeMetrics.selectionRingCornerRadius(
                isCircle: false,
                cameraScale: 2,
                cardCornerRadius: 24
            ) == 50
        )
    }
}
