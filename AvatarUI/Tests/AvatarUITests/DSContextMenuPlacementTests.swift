import AppKit
import SwiftUI
import XCTest
@testable import AvatarUI

final class DSContextMenuPlacementTests: XCTestCase {

    func testLocalAnchorSubtractsOverlayOrigin() {
        // Gallery-klik in window-space, overlay op de shell (origin ≠ gallery).
        let click = CGRect(x: 420, y: 360, width: 0, height: 0)
        let local = DSContextMenuPlacement.localAnchor(
            click,
            overlayGlobalOrigin: CGPoint(x: 0, y: 0)
        )
        XCTAssertEqual(local.origin.x, 420)
        XCTAssertEqual(local.origin.y, 360)

        let inset = DSContextMenuPlacement.localAnchor(
            click,
            overlayGlobalOrigin: CGPoint(x: 248, y: 52)
        )
        XCTAssertEqual(inset.origin.x, 172)
        XCTAssertEqual(inset.origin.y, 308)
    }

    func testPointAnchorOpensAtClick() {
        let click = CGRect(x: 80, y: 120, width: 0, height: 0)
        let origin = DSContextMenuPlacement.offset(
            anchor: click,
            menuSize: CGSize(width: 220, height: 260),
            in: CGSize(width: 1200, height: 800)
        )
        XCTAssertEqual(origin.x, 80)
        XCTAssertEqual(origin.y, 120 + DSSpacing.gap2)
    }

    func testRectAnchorOpensBelowLeadingEdge() {
        let row = CGRect(x: 16, y: 88, width: 200, height: 32)
        let origin = DSContextMenuPlacement.offset(
            anchor: row,
            menuSize: CGSize(width: 220, height: 260),
            in: CGSize(width: 1200, height: 800)
        )
        XCTAssertEqual(origin.x, 16)
        XCTAssertEqual(origin.y, row.maxY + DSSpacing.gap2)
    }

    func testClampsOntoScreenNearClick() {
        let click = CGRect(x: 1100, y: 720, width: 0, height: 0)
        let origin = DSContextMenuPlacement.offset(
            anchor: click,
            menuSize: CGSize(width: 220, height: 260),
            in: CGSize(width: 1200, height: 800)
        )
        XCTAssertEqual(origin.x, 1200 - 220 - DSSpacing.gap2)
        XCTAssertEqual(origin.y, 800 - 260 - DSSpacing.gap2)
    }

    @MainActor
    func testAccessoryWidensRowInsteadOfOverlayingShortcut() {
        let shortcut = "Sharper · Cloud"
        let without = DSMenuRow("Online", icon: "cloud", shortcut: shortcut) {}
        let withBadge = DSMenuRow("Online", icon: "cloud", shortcut: shortcut) {
            DSPrivacyBadge(tier: .thirdParty)
        } action: {}

        let hostWithout = NSHostingView(rootView: without)
        let hostWith = NSHostingView(rootView: withBadge)
        hostWithout.layout()
        hostWith.layout()

        XCTAssertGreaterThan(
            hostWith.fittingSize.width,
            hostWithout.fittingSize.width,
            "Privacy badge must sit in-flow so shortcut text is not covered"
        )
        XCTAssertNotNil(ImageRenderer(content: withBadge).cgImage)
    }
}
