// E06.1 — editor-framework: de zes tools uit App / Edit zijn compleet
// gedefinieerd (label, icoon, pending-story) en de toolbar-items dekken
// alle cases.

import XCTest
@testable import Avatar2

final class EditorToolTests: XCTestCase {

    func testAlleToolsCompleetGedefinieerd() {
        XCTAssertEqual(EditorTool.allCases.count, 6)
        for tool in EditorTool.allCases {
            XCTAssertFalse(tool.label.isEmpty)
            XCTAssertFalse(tool.pendingStory.isEmpty)
        }
        XCTAssertEqual(
            EditorTool.allCases.map(\.label),
            ["Edit", "Effects", "Clothing", "Hair", "Background", "Images"]
        )
    }
}
