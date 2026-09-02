import AppKit
import SwiftUI
import XCTest
@testable import AvatarUI

final class DSSliderTests: XCTestCase {

    @MainActor
    func testRendersAtDefaultRange() {
        let view = DSSlider(value: .constant(0.5), in: 0...1)
            .frame(width: 200)
        XCTAssertNotNil(view)
    }

    @MainActor
    func testRendersAtSignedRange() {
        let view = DSSlider(value: .constant(0), in: -0.4...0.4)
            .frame(width: 200)
        XCTAssertNotNil(view)
    }

    @MainActor
    func testCompactHitHeightFitsA24ptTarget() {
        let view = DSSlider(value: .constant(0.5), in: 0...1)
        let host = NSHostingView(rootView: view.frame(width: 200))
        host.layout()
        XCTAssertGreaterThanOrEqual(host.fittingSize.height, 24)
        XCTAssertLessThanOrEqual(host.fittingSize.height, 28)
    }

    @MainActor
    func testRendersGradientTrack() {
        let view = DSSlider(
            value: .constant(0),
            in: -1...1,
            track: .gradient([.blue, .white, .orange])
        )
        .frame(width: 200)
        let host = NSHostingView(rootView: view)
        host.layout()
        XCTAssertGreaterThanOrEqual(host.fittingSize.height, 24)
    }

    func testSnapOnlyClamps() {
        XCTAssertEqual(DSSlider.snap(1.5, in: 0...1, step: nil), 1)
        XCTAssertEqual(DSSlider.snap(-0.2, in: 0...1, step: nil), 0)
        XCTAssertEqual(DSSlider.snap(0.4, in: 0...1, step: nil), 0.4)
        // Display +2 (raw 0.02) mag niet naar 0 — ticks zijn visueel.
        XCTAssertEqual(DSSlider.snap(0.02, in: -0.4...0.4, step: 0.1), 0.02, accuracy: 0.0001)
        XCTAssertEqual(DSSlider.snap(0.14, in: -0.4...0.4, step: 0.1), 0.14, accuracy: 0.0001)
    }

    func testNearestTickAlwaysRounds() {
        XCTAssertEqual(DSSlider.nearestTick(0.14, in: -0.4...0.4, step: 0.1), 0.1, accuracy: 0.0001)
        XCTAssertEqual(DSSlider.nearestTick(-0.36, in: -0.4...0.4, step: 0.1), -0.4, accuracy: 0.0001)
    }

    @MainActor
    func testRendersSteppedTrack() {
        let view = DSSlider(value: .constant(0), in: -0.4...0.4, step: 0.1)
            .frame(width: 200)
        let host = NSHostingView(rootView: view)
        host.layout()
        XCTAssertGreaterThanOrEqual(host.fittingSize.height, 24)
    }
}
