import SwiftUI
import XCTest
@testable import AvatarUI

final class DSSelectionCheckBadgeTests: XCTestCase {

    @MainActor
    func testRendersAtDefaultSize() {
        let view = DSSelectionCheckBadge()
            .frame(width: 24, height: 24)
        XCTAssertNotNil(view)
    }

    @MainActor
    func testRendersAtCustomSize() {
        let view = DSSelectionCheckBadge(size: 22)
            .frame(width: 28, height: 28)
        XCTAssertNotNil(view)
    }
}
