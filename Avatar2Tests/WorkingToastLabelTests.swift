// E55.9 — de verstreken-tijd-regel van de working-toast: eerlijk doortellen,
// minuut-afronding in de verwachting, en voorbij de verwachting geen
// "usually" meer beloven.

import XCTest
@testable import Avatar2

final class WorkingToastLabelTests: XCTestCase {

    func testPlainStampWithoutExpectation() {
        XCTAssertEqual(WorkingToastView.elapsedLabel(0, expected: nil), "0:00")
        XCTAssertEqual(WorkingToastView.elapsedLabel(72, expected: nil), "1:12")
    }

    func testExpectationHintRoundsToMinutes() {
        XCTAssertEqual(WorkingToastView.elapsedLabel(12, expected: 75), "0:12 · usually ~1 min")
        XCTAssertEqual(WorkingToastView.elapsedLabel(5, expected: 110), "0:05 · usually ~2 min")
        XCTAssertEqual(WorkingToastView.elapsedLabel(5, expected: 45), "0:05 · usually ~45s")
    }

    func testPastExpectationSwitchesToStillWorking() {
        XCTAssertEqual(WorkingToastView.elapsedLabel(76, expected: 75), "1:16 · still working…")
        // Exact op de grens nog gewoon de verwachting tonen.
        XCTAssertEqual(WorkingToastView.elapsedLabel(75, expected: 75), "1:15 · usually ~1 min")
    }
}
