// UXS-10 / UX9 — de zwevende upload-pil mag de onderste kaartrij niet maskeren.

import AvatarUI
import XCTest
@testable import Avatar2

final class UploadPillInsetTests: XCTestCase {

    /// De scroll-inset moet de hele pil vrijhouden: hoogte + de afstand tot de
    /// vensterrand. Zonder marge zou het label van de onderste rij precies tegen
    /// de pil-rand plakken, dus er hoort lucht overheen te zitten.
    func testScrollInsetClearsTheWholePill() {
        let pillFootprint = ShellMetrics.uploadPillHeight + ShellMetrics.uploadPillBottomInset
        XCTAssertGreaterThan(
            ShellMetrics.uploadPillScrollInset, pillFootprint,
            "de inset moet de pil én wat lucht vrijhouden (UX9)"
        )
    }

    /// Afgeleid, niet los ingetypt: als de pil verandert schuift de inset mee.
    /// Deze test faalt zodra iemand er weer een magic number van maakt.
    func testScrollInsetIsDerivedFromPillMetrics() {
        XCTAssertEqual(
            ShellMetrics.uploadPillScrollInset,
            ShellMetrics.uploadPillHeight + ShellMetrics.uploadPillBottomInset + DSSpacing.gap4,
            accuracy: 0.001
        )
    }
}
