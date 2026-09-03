import AppKit
import AvatarUI
import SwiftUI
import XCTest
@testable import Avatar2

@MainActor
final class EnhanceActionTileTests: XCTestCase {

    func testHoverLiftsImageInsideClip() {
        XCTAssertEqual(
            EnhanceTileMetrics.imageShift(hovering: true, reduceMotion: false),
            -EnhanceTileMetrics.hoverLift
        )
        XCTAssertEqual(EnhanceTileMetrics.imageShift(hovering: true, reduceMotion: true), 0)
        XCTAssertEqual(EnhanceTileMetrics.imageShift(hovering: false, reduceMotion: false), 0)
        XCTAssertGreaterThan(EnhanceTileMetrics.hoverLift, 0)
    }

    func testPlateSharesTitleLeadingInset() {
        XCTAssertEqual(EnhanceTileMetrics.contentInset, DSSpacing.gap3)
    }

    func testTilesShareFixedHeight() {
        XCTAssertEqual(EnhanceTileMetrics.height, 176)
        XCTAssertEqual(
            EnhanceTileMetrics.panelContentHeight,
            3 * EnhanceTileMetrics.height + 2 * EnhanceTileMetrics.gridSpacing
        )
        XCTAssertEqual(EnhanceTileMetrics.columns, 3)
        // Vierkant: "Remove background ⌄" (137pt) past op één regel.
        XCTAssertEqual(EnhanceTileMetrics.tileWidth, EnhanceTileMetrics.height)
        XCTAssertEqual(
            EnhanceTileMetrics.panelWidth,
            3 * EnhanceTileMetrics.tileWidth + 2 * EnhanceTileMetrics.gridSpacing
                + 2 * (DSSpacing.gap5 + DSSpacing.gap2)
        )
        XCTAssertEqual(EnhanceTileMetrics.contentInset, DSSpacing.gap3)
        XCTAssertEqual(EnhanceTileMetrics.headerImageGap, DSSpacing.gap3)
        // Eén regel labelSmall + top-inset.
        XCTAssertEqual(
            EnhanceTileMetrics.headerHeight,
            EnhanceTileMetrics.contentInset + DSTypography.LineHeight.xs
        )
    }

    func testTileRendersAtFixedHeightWithBadge() {
        let img = sampleImage()
        let view = EnhanceActionTile(
            title: "Boost",
            credit: "3",
            layers: EnhanceTileLayers(base: img, reveal: img, subject: img),
            motion: .wipeHorizontal(rest: 0.5, from: .leading),
            fallback: img,
            action: {}
        )
        .frame(width: 180, height: EnhanceTileMetrics.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let cg = renderer.cgImage
        XCTAssertNotNil(cg)
        XCTAssertEqual(cg?.width, 180)
        XCTAssertEqual(cg?.height, Int(EnhanceTileMetrics.height))
    }

    // MARK: - E53.10 motion

    func testMotionRestStates() {
        XCTAssertEqual(EnhanceTileMotion.none.rest, 0)
        XCTAssertEqual(EnhanceTileMotion.wipeHorizontal(rest: 0.5, from: .trailing).rest, 0.5)
        XCTAssertEqual(EnhanceTileMotion.wipeVertical(rest: 0.55).rest, 0.55)
        XCTAssertEqual(EnhanceTileMotion.spotlight.rest, 0)
        XCTAssertEqual(EnhanceTileMotion.depthPull.rest, 0)
        // Remove background toont in rust de checker (= reveal).
        XCTAssertEqual(EnhanceTileMotion.dissolve.rest, 1)
        XCTAssertEqual(EnhanceTileMotion.dissolve.start, 0, "hover-in begint bij de originele achtergrond")
        XCTAssertEqual(EnhanceTileMotion.resolve.rest, 0)
        XCTAssertFalse(EnhanceTileMotion.resolve.animatesExit)
        XCTAssertEqual(EnhanceTileMotion.wipeVertical(rest: 0.55).start, 0.55)
    }

    func testMotionTargetHonoursHoverAndReduceMotion() {
        let wipe = EnhanceTileMotion.wipeHorizontal(rest: 0.5, from: .leading)
        XCTAssertEqual(EnhanceTileMotion.target(wipe, hovering: false, reduceMotion: false), 0.5)
        XCTAssertEqual(EnhanceTileMotion.target(wipe, hovering: true, reduceMotion: false), 1)
        XCTAssertEqual(EnhanceTileMotion.target(wipe, hovering: true, reduceMotion: true), 0.5)
        XCTAssertEqual(EnhanceTileMotion.target(.dissolve, hovering: true, reduceMotion: true), 1)
        XCTAssertEqual(EnhanceTileMotion.target(.none, hovering: true, reduceMotion: false), 0)
    }

    func testSequenceCurves() {
        // Dissolve: start én eind op checker (geen sprong bij hover-in/-out),
        // origineel fade-in → hold → fade-out → zachte blink → checker.
        XCTAssertEqual(EnhanceMotionCurves.dissolve(0), 1)
        XCTAssertEqual(EnhanceMotionCurves.dissolve(0.3), 0)
        XCTAssertEqual(EnhanceMotionCurves.dissolve(0.58), 1)
        XCTAssertLessThan(EnhanceMotionCurves.dissolve(0.68), 0.7)
        XCTAssertEqual(EnhanceMotionCurves.dissolve(1), 1)
        // Spot: uit aan begin en eind, piek ≤ 0.5 (geen overbelichting), straal groeit.
        XCTAssertEqual(EnhanceMotionCurves.spotlightAlpha(0), 0)
        XCTAssertEqual(EnhanceMotionCurves.spotlightAlpha(0.5), 0.45)
        XCTAssertEqual(EnhanceMotionCurves.spotlightAlpha(1), 0)
        XCTAssertGreaterThan(EnhanceMotionCurves.spotlightRadius(1), EnhanceMotionCurves.spotlightRadius(0))
        XCTAssertGreaterThan(EnhanceTileMotion.dissolve.duration, EnhanceTileMetrics.motionDuration)
    }

    func testSpotlightAndDissolveSnapBackInsteadOfAnimatingExit() {
        XCTAssertFalse(EnhanceTileMotion.spotlight.animatesExit)
        XCTAssertFalse(EnhanceTileMotion.dissolve.animatesExit)
        XCTAssertTrue(EnhanceTileMotion.wipeHorizontal(rest: 0.5, from: .leading).animatesExit)
        XCTAssertTrue(EnhanceTileMotion.depthPull.animatesExit)
    }

    func testResolveFrameIndexStepsThroughLadder() {
        // 5 frames (4 stappen + scherp): base tot 0.2, daarna stap voor stap, 1.0 = scherp.
        XCTAssertNil(EnhanceResolveFrames.frameIndex(progress: 0, count: 5))
        XCTAssertNil(EnhanceResolveFrames.frameIndex(progress: 0.19, count: 5))
        XCTAssertEqual(EnhanceResolveFrames.frameIndex(progress: 0.2, count: 5), 0)
        XCTAssertEqual(EnhanceResolveFrames.frameIndex(progress: 0.5, count: 5), 1)
        XCTAssertEqual(EnhanceResolveFrames.frameIndex(progress: 0.99, count: 5), 3)
        XCTAssertEqual(EnhanceResolveFrames.frameIndex(progress: 1, count: 5), 4)
        XCTAssertNil(EnhanceResolveFrames.frameIndex(progress: 1, count: 0))
    }

    func testPortraitScenesAreBundled() {
        XCTAssertEqual(EnhancePreviewScenes.names.count, 3)
        for name in EnhancePreviewScenes.names {
            XCTAssertNotNil(EnhancePreviewScenes.image(named: name), "scène \(name) ontbreekt in de asset catalog")
        }
        XCTAssertNotNil(EnhancePreviewScenes.random())
    }

    private func sampleImage() -> NSImage {
        let size = NSSize(width: 48, height: 48)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}
