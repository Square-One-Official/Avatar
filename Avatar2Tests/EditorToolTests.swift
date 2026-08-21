// E06.1 / E21.1 — editor-framework: de tools uit App / Edit zijn compleet
// gedefinieerd (label, icoon) en de toolbar-items dekken alle cases.
// E21.1 voegde de Face-tool toe (beauty, gesplitst uit Edit).

import AvatarKit
import XCTest
@testable import Avatar2

final class EditorToolTests: XCTestCase {

    func testAlleToolsCompleetGedefinieerd() {
        XCTAssertEqual(EditorTool.allCases.count, 7)
        for tool in EditorTool.allCases {
            XCTAssertFalse(tool.label.isEmpty)
        }
        XCTAssertEqual(
            EditorTool.allCases.map(\.label),
            ["Edit", "Effects", "Face", "Clothing", "Hair", "Background", "Images"]
        )
    }

    /// Face/Hair/Clothing blijven achter de compile-time poort, ook als de CMS
    /// alles aan zet (prod-default). Effects volgt wél alleen de remote flag.
    func testUnreleasedToolsHiddenWhenRemoteAllowsThem() {
        let flags = RemoteFeatureFlags.allEnabled
        XCTAssertTrue(EditorTool.edit.isEnabled(remote: flags))
        XCTAssertTrue(EditorTool.effects.isEnabled(remote: flags))
        XCTAssertFalse(EditorTool.face.isEnabled(remote: flags))
        XCTAssertFalse(EditorTool.hair.isEnabled(remote: flags))
        XCTAssertFalse(EditorTool.clothing.isEnabled(remote: flags))
    }

    func testRemoteFlagHidesEffectsEvenWhenCompileTimeAllows() {
        let flags = RemoteFeatureFlags(
            effectsEnabled: false,
            hairEnabled: true,
            clothesEnabled: true,
            faceEnabled: true,
            backgroundsEnabled: true
        )
        XCTAssertFalse(EditorTool.effects.isEnabled(remote: flags))
        XCTAssertTrue(EditorTool.edit.isEnabled(remote: flags))
    }
}
