// Plaatsing van de zwevende child-vensters (DSFloatingWindow): menu's klemmen
// op het schérm (niet op het venster), toasts op de hoek van het hostvenster;
// de panel is de clip-regio en de hosting view (inhoud + schaduwmarge) ligt
// daar relatief in.

import AppKit
import SwiftUI
import XCTest
@testable import AvatarUI

final class DSFloatingLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 860)
    private let parent = CGRect(x: 200, y: 100, width: 1000, height: 600)

    func testMenuOpensAtAnchorTopLeft() {
        let frame = DSFloatingLayout.contentFrame(
            placement: .anchoredTopLeft(CGPoint(x: 500, y: 400), bounds: .screen),
            size: CGSize(width: 220, height: 300),
            parent: parent, screen: screen
        )
        XCTAssertEqual(frame.minX, 500)
        XCTAssertEqual(frame.maxY, 400, "linkerbovenhoek op het anker (y omhoog → maxY)")
        XCTAssertEqual(frame.height, 300)
    }

    func testMenuMayLeaveParentWindowButClampsToScreen() {
        // Anker onderin het venster: het menu steekt onder de vensterrand uit
        // (parent.minY = 100) maar blijft binnen het scherm.
        let frame = DSFloatingLayout.contentFrame(
            placement: .anchoredTopLeft(CGPoint(x: 1300, y: 150), bounds: .screen),
            size: CGSize(width: 220, height: 300),
            parent: parent, screen: screen
        )
        XCTAssertLessThan(frame.minY, parent.minY, "mag buiten het hostvenster")
        XCTAssertEqual(frame.minY, screen.minY + DSSpacing.gap2)
        XCTAssertEqual(frame.maxX, screen.maxX - DSSpacing.gap2)
        XCTAssertEqual(
            DSFloatingLayout.clipRect(placement: .anchoredTopLeft(.zero, bounds: .screen), parent: parent, screen: screen),
            screen
        )
    }

    func testWindowBoundedPanelStaysInsideParent() {
        // Achtergrond-kiezer (440 breed) geopend op een klik rechtsonder in
        // het venster: schuift naar binnen i.p.v. over de vensterrand.
        let placement = DSFloatingLayout.Placement.anchoredTopLeft(CGPoint(x: 1100, y: 250), bounds: .window)
        let frame = DSFloatingLayout.contentFrame(
            placement: placement,
            size: CGSize(width: 472, height: 560),
            parent: parent, screen: screen
        )
        XCTAssertEqual(frame.maxX, parent.maxX - DSSpacing.gap2)
        XCTAssertEqual(frame.minY, parent.minY + DSSpacing.gap2)
        XCTAssertGreaterThanOrEqual(frame.minX, parent.minX)
        XCTAssertLessThanOrEqual(frame.maxY, parent.maxY)
        // De schaduw mag wél over de vensterrand (clip = scherm, als een popover).
        XCTAssertEqual(DSFloatingLayout.clipRect(placement: placement, parent: parent, screen: screen), screen)
    }

    func testWindowBoundedPanelFallsBackToScreenWhenParentIsTooSmall() {
        // Venster grotendeels van het scherm af (zichtbaar deel 240 breed):
        // het paneel past daar niet in → klemmen op het scherm, per as.
        let offscreenParent = CGRect(x: 1200, y: 100, width: 1000, height: 600)
        let frame = DSFloatingLayout.contentFrame(
            placement: .anchoredTopLeft(CGPoint(x: 2000, y: 600), bounds: .window),
            size: CGSize(width: 472, height: 400),
            parent: offscreenParent, screen: screen
        )
        XCTAssertEqual(frame.maxX, screen.maxX - DSSpacing.gap2)
        XCTAssertEqual(frame.maxY, 600, "verticaal past het wél in het venster → op het anker")
        // Paneel hoger dan het venster: verticaal op het scherm, horizontaal in het venster.
        let tall = DSFloatingLayout.contentFrame(
            placement: .anchoredTopLeft(CGPoint(x: 900, y: 150), bounds: .window),
            size: CGSize(width: 472, height: 700),
            parent: parent, screen: screen
        )
        XCTAssertEqual(tall.maxX, parent.maxX - DSSpacing.gap2)
        XCTAssertEqual(tall.minY, screen.minY + DSSpacing.gap2)
    }

    func testMarginsContainTheFullShadowBlur() {
        // Menu: dsMenuSurface-schaduw (radius 12, y 12) → 36 opzij, 24 boven, 48 onder.
        let menu = DSFloatingMode.menu(onDismiss: {}).margin
        XCTAssertEqual(menu.left, DSPanelShadow.radius * DSFloatingMode.shadowBlurExtent)
        XCTAssertEqual(menu.right, menu.left)
        XCTAssertEqual(menu.top, menu.left - DSPanelShadow.yOffset)
        XCTAssertEqual(menu.bottom, menu.left + DSPanelShadow.yOffset)
        // Toast: gehalveerde Shadows/Default.
        let toast = DSFloatingMode.toast.margin
        let toastRadius = DSShadow.default.radius / 2
        XCTAssertEqual(toast.left, toastRadius * DSFloatingMode.shadowBlurExtent)
        XCTAssertEqual(toast.bottom, toast.left + DSShadow.default.offset.height / 2)
    }

    func testOversizedMenuKeepsTopAndLeadingEdgeVisible() {
        let frame = DSFloatingLayout.contentFrame(
            placement: .anchoredTopLeft(CGPoint(x: 700, y: 500), bounds: .screen),
            size: CGSize(width: 2000, height: 2000),
            parent: parent, screen: screen
        )
        XCTAssertEqual(frame.minX, screen.minX + DSSpacing.gap2)
        XCTAssertEqual(frame.maxY, screen.maxY - DSSpacing.gap2)
    }

    func testToastSitsInBottomTrailingCornerOfParent() {
        let size = CGSize(width: 360, height: 80)
        let frame = DSFloatingLayout.contentFrame(
            placement: .corner(.bottomTrailing, padding: 20),
            size: size, parent: parent, screen: screen
        )
        XCTAssertEqual(frame.maxX, parent.maxX - 20)
        XCTAssertEqual(frame.minY, parent.minY + 20)
        XCTAssertEqual(
            DSFloatingLayout.clipRect(placement: .corner(.bottomTrailing, padding: 20), parent: parent, screen: screen),
            parent
        )
    }

    func testFramesClipBleedToParentAndOffsetHostingView() {
        // Toast rechtsonder: de schaduwmarge steekt onder/rechts het venster
        // uit → panel = doorsnede met parent; hosting view schuift negatief.
        let content = CGRect(x: 820, y: 120, width: 360, height: 80)
        let margin = NSEdgeInsets(top: 40, left: 80, bottom: 120, right: 80)
        let frames = DSFloatingLayout.frames(content: content, margin: margin, clip: parent)
        XCTAssertEqual(frames.panel, CGRect(x: 740, y: 100, width: 460, height: 140))
        XCTAssertEqual(frames.hosting.origin, CGPoint(x: 0, y: -120 + 20))
        XCTAssertEqual(frames.hosting.size, CGSize(width: 520, height: 240))
        // De inhoud landt op z'n schermpositie: panel.origin + hosting.origin + marge.
        XCTAssertEqual(frames.panel.minX + frames.hosting.minX + margin.left, content.minX)
        XCTAssertEqual(frames.panel.minY + frames.hosting.minY + margin.bottom, content.minY)
    }

    func testFramesWithoutClippingKeepHostingAtOrigin() {
        let content = CGRect(x: 500, y: 300, width: 200, height: 100)
        let margin = NSEdgeInsets(top: 12, left: 24, bottom: 36, right: 24)
        let frames = DSFloatingLayout.frames(content: content, margin: margin, clip: screen)
        XCTAssertEqual(frames.panel, CGRect(x: 476, y: 264, width: 248, height: 148))
        XCTAssertEqual(frames.hosting, CGRect(origin: .zero, size: frames.panel.size))
    }

    func testMenuPreferredTopLeftUsesClickOrElementBottom() {
        let click = CGRect(x: 80, y: 120, width: 0, height: 0)
        XCTAssertEqual(
            DSContextMenuPlacement.preferredTopLeft(anchor: click),
            CGPoint(x: 80, y: 120 + DSSpacing.gap2)
        )
        let row = CGRect(x: 16, y: 88, width: 200, height: 32)
        XCTAssertEqual(
            DSContextMenuPlacement.preferredTopLeft(anchor: row),
            CGPoint(x: 16, y: row.maxY + DSSpacing.gap2)
        )
    }
}
