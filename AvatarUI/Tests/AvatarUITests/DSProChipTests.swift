// Smoke-tests voor E03.4/E03.7: body-evaluatie van DSProChip, DSGated en
// de per-feature-indicatoren.

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

    @MainActor
    func testFeatureIndicatorenRenderen() {
        XCTAssertNotNil(ImageRenderer(content: DSFeatureIndicator(.pro) {}).cgImage)
        XCTAssertNotNil(ImageRenderer(content: DSFeatureIndicator(.cloudOff) {}).cgImage)
    }

    @MainActor
    func testGatedRendertCloudGlyphAlleenAlsOnlineVereistEnUit() {
        for (locked, requiresOnline, online) in
            [(true, true, false), (false, true, false), (false, true, true)] {
            let view = DSGated(
                isLocked: locked,
                requiresOnline: requiresOnline,
                isOnlineEnabled: online,
                onUpgradeRequested: {},
                onOpenAISettings: {}
            ) {
                DSPrimaryButton("Whiten teeth") {}
            }
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }
}
