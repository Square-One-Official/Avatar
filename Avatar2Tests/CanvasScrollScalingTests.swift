// E27.9 (audit C2) — muiswiel-scroll-schaling: line-deltas (muiswiel,
// `hasPreciseScrollingDeltas == false`) moeten naar punten geschaald worden;
// trackpad-punt-deltas blijven 1:1 (bestaand gedrag ongewijzigd).

import CoreGraphics
import Testing
@testable import Avatar2

@Suite struct CanvasScrollScalingTests {

    // MARK: - Pan

    @Test func trackpadPanDeltasPassThroughUnchanged() {
        #expect(CanvasInteractionCatcher.scrollPanDelta(3.5, precise: true) == 3.5)
        #expect(CanvasInteractionCatcher.scrollPanDelta(-12, precise: true) == -12)
    }

    @Test func mouseWheelLineDeltasScaleToPoints() {
        // Eén wiel-tik (~1 line) moet in de plan-band ×20–40 landen — niet ~0,75pt.
        let tick = CanvasInteractionCatcher.scrollPanDelta(1, precise: false)
        #expect(tick >= 20 && tick <= 40)
        // Richting blijft behouden.
        #expect(CanvasInteractionCatcher.scrollPanDelta(-1, precise: false) == -tick)
    }

    // MARK: - ⌘-scroll-zoom

    @Test func trackpadZoomFactorUnchanged() {
        // Bestaande formule 1 − Δy·0.01, ongeclampt (trackpad-gevoel intact).
        let f = CanvasInteractionCatcher.scrollZoomFactor(deltaY: 10, precise: true)
        #expect(abs(f - 0.9) < 0.0001)
    }

    @Test func mouseWheelZoomTickIsNoticeable() {
        // Eén tik omhoog (Δy = −1) moet merkbaar inzoomen (was ~1% per tik).
        let zoomIn = CanvasInteractionCatcher.scrollZoomFactor(deltaY: -1, precise: false)
        #expect(zoomIn > 1.1)
        let zoomOut = CanvasInteractionCatcher.scrollZoomFactor(deltaY: 1, precise: false)
        #expect(zoomOut < 0.9)
    }

    @Test func mouseWheelZoomFactorIsClamped() {
        // macOS-scroll-versnelling kan grote line-deltas sturen — de factor
        // blijft geclampt zodat de zoom niet in één event springt.
        let bigIn = CanvasInteractionCatcher.scrollZoomFactor(deltaY: -30, precise: false)
        #expect(bigIn <= 1.33)
        let bigOut = CanvasInteractionCatcher.scrollZoomFactor(deltaY: 30, precise: false)
        #expect(bigOut >= 0.75)
    }
}
