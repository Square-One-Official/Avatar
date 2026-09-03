// UXS-3 / UX5 — de scrim onder kaartlabels moet wit tekst leesbaar houden op
// élke foto, ook een zuiver witte cutout in light mode.

import SwiftUI
import XCTest
@testable import AvatarUI

final class DSCardLabelScrimTests: XCTestCase {

    /// WCAG AA voor normale tekst = 4.5:1. Het slechtste geval is wit label op
    /// de scrim over een zuiver witte ondergrond; die ondergrens borgen we hier
    /// zodat een latere "iets subtielere" scrim niet stilletjes onder AA zakt.
    func testPlateauKeepsWhiteLabelAboveWCAGAA() {
        let ratio = DSCardLabelScrim.contrastRatioOnWhite()
        XCTAssertGreaterThanOrEqual(
            ratio, 4.5,
            "wit label op de scrim haalt \(ratio):1 — onder de 4.5:1-ondergrens (UX5)"
        )
    }

    /// De oude waarde (0.55) haalde het nét op de ONDERrand van de kaart, maar
    /// het label zit door z'n padding hoger in de ramp — vandaar het plateau.
    /// Deze test legt vast dat we boven die oude waarde zitten.
    func testPlateauIsDarkerThanTheOldRampEnd() {
        XCTAssertGreaterThan(DSCardLabelScrim.plateauOpacity, 0.55)
    }

    func testContrastRatioGrowsWithOpacity() {
        XCTAssertLessThan(
            DSCardLabelScrim.contrastRatioOnWhite(opacity: 0.4),
            DSCardLabelScrim.contrastRatioOnWhite(opacity: 0.8)
        )
    }

    func testScrimRenders() {
        let view = DSCardLabelScrim().frame(width: 120, height: 160)
        XCTAssertNotNil(NSHostingView(rootView: view))
    }
}
