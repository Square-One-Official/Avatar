import SwiftUI
import XCTest
@testable import AvatarUI

final class DSSegmentedControlTests: XCTestCase {

    private enum Tab: Hashable { case a, b, c }

    @MainActor
    func testRendertAlleSegmenten() {
        let view = DSSegmentedControl(
            selection: .constant(.a),
            segments: [
                .init(tag: Tab.a, label: "One"),
                .init(tag: Tab.b, label: "Two"),
                .init(tag: Tab.c, label: "Three"),
            ],
            equalWidth: true
        )
        .frame(width: 320)

        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }
}
