import XCTest
@testable import AvatarUI

final class AvatarUITests: XCTestCase {
    func testVersieAnker() {
        XCTAssertFalse(AvatarUIInfo.version.isEmpty)
    }
}

// E03.15 — concentrische kaartradius
extension AvatarUITests {

    func testConcentrischeRadius() {
        XCTAssertEqual(DSRadius.concentric(inset: 4), DSRadius.window - 4)
        XCTAssertEqual(DSRadius.concentric(inset: DSRadius.window + 10), 0)
    }
}
