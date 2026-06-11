import XCTest
@testable import AvatarUI

final class AvatarUITests: XCTestCase {
    func testVersieAnker() {
        XCTAssertFalse(AvatarUIInfo.version.isEmpty)
    }
}
