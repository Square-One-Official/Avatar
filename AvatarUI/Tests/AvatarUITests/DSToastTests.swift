// E50.3 — DSToast-actieslot: de timer hertelt óók bij een andere actie, en de
// actie-knop is een gewone closure-drager.

import SwiftUI
import XCTest
@testable import AvatarUI

final class DSToastTests: XCTestCase {
    func testTimerKeyIncludesActionLabel() {
        let plain = DSToast.timerKey(title: "Matched", description: nil, actionLabel: nil)
        let withUndo = DSToast.timerKey(title: "Matched", description: nil, actionLabel: "Undo")
        XCTAssertNotEqual(plain, withUndo, "een vervangende melding mét actie krijgt de volle duur")
        XCTAssertEqual(plain, DSToast.timerKey(title: "Matched", description: nil, actionLabel: nil))
    }

    func testActionCarriesLabelAndHandler() {
        var fired = false
        let action = DSToastAction("Undo") { fired = true }
        XCTAssertEqual(action.label, "Undo")
        action.handler()
        XCTAssertTrue(fired)
    }

    func testToastBuildsWithAndWithoutAction() {
        _ = DSToast(title: "Matched lighting on 2 portraits")
        _ = DSToast(title: "Matched lighting on 2 portraits", onClose: {}, action: DSToastAction("Undo") {})
    }
}
