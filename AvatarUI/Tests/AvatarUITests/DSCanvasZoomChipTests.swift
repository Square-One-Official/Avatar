// UXS-6/UXS-16 — de zoom-chip is gedeeld door editor, board en Banner Studio.
// Het percentage is relatief aan de FIT-stand (fit = 100%), niet aan de absolute
// schaal: "100%" moet "alles past" betekenen. Actual Size (1 punt per pixel)
// heeft z'n eigen sneltoets (⌘1).

import SwiftUI
import XCTest
@testable import AvatarUI

final class DSCanvasZoomChipTests: XCTestCase {

    func testFitStateReadsAsHundredPercent() {
        XCTAssertEqual(DSCanvasZoomChip.percentLabel(scale: 0.42, fitScale: 0.42), "100%")
    }

    func testZoomedInAndOutScaleRelativeToFit() {
        XCTAssertEqual(DSCanvasZoomChip.percentLabel(scale: 0.84, fitScale: 0.42), "200%")
        XCTAssertEqual(DSCanvasZoomChip.percentLabel(scale: 0.21, fitScale: 0.42), "50%")
    }

    /// Een chip die "0%" toont is misleidend — ver uitgezoomd blijft het
    /// minimaal 1%.
    func testNeverShowsZeroPercent() {
        XCTAssertEqual(DSCanvasZoomChip.percentLabel(scale: 0.0001, fitScale: 100), "1%")
    }

    /// Vóór de eerste layout is de viewport 0×0 en kan de fit-schaal nog nul of
    /// NaN zijn; de chip mag dan geen "NaN%" of een crash opleveren.
    func testDegenerateInputFallsBackToHundred() {
        XCTAssertEqual(DSCanvasZoomChip.percentLabel(scale: 1, fitScale: 0), "100%")
        XCTAssertEqual(DSCanvasZoomChip.percentLabel(scale: .nan, fitScale: 1), "100%")
        XCTAssertEqual(DSCanvasZoomChip.percentLabel(scale: 1, fitScale: .infinity), "100%")
    }

    func testBothVariantsRender() {
        XCTAssertNotNil(NSHostingView(rootView: DSCanvasZoomChip(scale: 1, fitScale: 1) {}))
        XCTAssertNotNil(NSHostingView(rootView: DSCanvasZoomChip(title: "Fit") {}))
    }
}
