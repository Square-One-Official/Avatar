// Smoke-tests voor E17.4 — body-evaluatie van DSMessageSheet + DSMessageBanner
// (rendert naar een afbeelding zodat de hele view-tree wordt opgebouwd),
// met en zonder image/CTA. Geen netwerk: AsyncImage valt terug op placeholder.

import SwiftUI
import XCTest
@testable import AvatarUI

final class DSMessageSheetTests: XCTestCase {
    @MainActor
    func testSheetRendertMetEnZonderImageEnCTA() {
        let variants: [(URL?, String?)] = [
            (nil, nil),
            (URL(string: "https://example.com/hero.png"), "Try it"),
            (nil, "Open"),
        ]
        for (url, cta) in variants {
            let view = DSMessageSheet(
                title: "Welcome to Aaavatar 2",
                body: "**New** styles, hair and clothing edits.",
                imageURL: url,
                ctaLabel: cta
            )
            .frame(width: 420)
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }

    @MainActor
    func testBannerRendertMetEnZonderCTA() {
        for hasCTA in [true, false] {
            let view = DSMessageBanner(
                title: "Tip",
                body: "Drag a photo to start.",
                imageURL: nil,
                hasCTA: hasCTA
            )
            .frame(width: 608)
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }
}
