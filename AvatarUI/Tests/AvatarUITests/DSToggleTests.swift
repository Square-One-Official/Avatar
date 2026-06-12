// Smoke-tests voor E03.6: body-evaluatie van DSToggle in beide standen
// en disabled.

import SwiftUI
import XCTest
@testable import AvatarUI

final class DSToggleTests: XCTestCase {

    @MainActor
    func testToggleRendertAanEnUit() {
        for on in [true, false] {
            let view = DSToggle(isOn: .constant(on))
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }

    @MainActor
    func testToggleRendertDisabled() {
        let view = DSToggle(isOn: .constant(false)).disabled(true)
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }
}
