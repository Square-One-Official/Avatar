// E06.1 / E21.1 — editor-framework: de tools uit App / Edit zijn compleet
// gedefinieerd (label, icoon, pending-story) en de toolbar-items dekken alle
// cases. E21.1 voegde de Face-tool toe (beauty, gesplitst uit Edit).

import XCTest
@testable import Avatar2

final class EditorToolTests: XCTestCase {

    func testAlleToolsCompleetGedefinieerd() {
        XCTAssertEqual(EditorTool.allCases.count, 7)
        for tool in EditorTool.allCases {
            XCTAssertFalse(tool.label.isEmpty)
            XCTAssertFalse(tool.pendingStory.isEmpty)
        }
        XCTAssertEqual(
            EditorTool.allCases.map(\.label),
            ["Edit", "Effects", "Face", "Clothing", "Hair", "Background", "Images"]
        )
    }

    /// GTM-cut 2026-08-16: launch-hidden flags fail closed (no DEBUG launch-arg).
    func testLaunchFeatureFlagsHideGTMCut() {
        XCTAssertFalse(AppFeatureFlags.bannersEnabled)
        XCTAssertFalse(AppFeatureFlags.faceEnabled)
        XCTAssertFalse(AppFeatureFlags.customEffectsEnabled)
        XCTAssertFalse(AppFeatureFlags.generateBackgroundEnabled)
        XCTAssertFalse(AppFeatureFlags.boostOnlineEnabled)
    }

    func testToolbarKeepsEffectsAndHidesFace() {
        XCTAssertTrue(EditorView.isToolbarToolVisible(.effects))
        XCTAssertTrue(EditorView.isToolbarToolVisible(.hair))
        XCTAssertTrue(EditorView.isToolbarToolVisible(.clothing))
        XCTAssertTrue(EditorView.isToolbarToolVisible(.edit))
        XCTAssertFalse(EditorView.isToolbarToolVisible(.face))
        XCTAssertFalse(EditorView.visibleToolbarItems.contains { $0.id == .face })
        XCTAssertTrue(EditorView.visibleToolbarItems.contains { $0.id == .effects })
    }
}
