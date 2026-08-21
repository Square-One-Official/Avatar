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
}
