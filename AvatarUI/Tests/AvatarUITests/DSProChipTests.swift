// Smoke-tests voor E03.4: body-evaluatie van DSProChip en DSGated in
// beide gate-standen.

import SwiftUI
import XCTest
@testable import AvatarUI

final class DSProChipTests: XCTestCase {

    @MainActor
    func testProChipRendert() {
        XCTAssertNotNil(ImageRenderer(content: DSProChip()).cgImage)
        XCTAssertNotNil(ImageRenderer(content: DSProChip("2 credits")).cgImage)
    }

    @MainActor
    func testGatedRendertVergrendeldEnOntgrendeld() {
        for locked in [true, false] {
            let view = DSGated(isLocked: locked, onUpgradeRequested: {}) {
                DSPrimaryButton("Whiten teeth") {}
            }
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }
}
