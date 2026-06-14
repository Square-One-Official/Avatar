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
}
