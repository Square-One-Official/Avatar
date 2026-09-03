// E55.9 — de tijdsregel van de working-toast: zonder verwachting een kale
// klok, mét verwachting de resterende tijd in gewone taal (op 5 s / hele
// minuten afgerond) en voorbij de verwachting een eerlijk "langer dan
// gewoonlijk" i.p.v. een belofte.

import XCTest
@testable import Avatar2

final class WorkingToastLabelTests: XCTestCase {

    func testPlainStampWithoutExpectation() {
        XCTAssertEqual(WorkingToastView.elapsedLabel(0, expected: nil), "0:00")
        XCTAssertEqual(WorkingToastView.elapsedLabel(72, expected: nil), "1:12")
    }

    func testRemainingMinutesRoundToWholeMinutes() {
        XCTAssertEqual(WorkingToastView.elapsedLabel(0, expected: 85), "About 1 minute left")
        XCTAssertEqual(WorkingToastView.elapsedLabel(5, expected: 110), "About 2 minutes left")
        XCTAssertEqual(WorkingToastView.elapsedLabel(0, expected: 60), "About 1 minute left")
        // 58 s rest → omhoog naar 60 → een minuut, geen "About 60 seconds".
        XCTAssertEqual(WorkingToastView.elapsedLabel(27, expected: 85), "About 1 minute left")
    }

    func testRemainingSecondsRoundUpToFive() {
        XCTAssertEqual(WorkingToastView.elapsedLabel(32, expected: 85), "About 55 seconds left")
        XCTAssertEqual(WorkingToastView.elapsedLabel(40, expected: 85), "About 45 seconds left")
        XCTAssertEqual(WorkingToastView.elapsedLabel(84, expected: 85), "About 5 seconds left")
        XCTAssertEqual(WorkingToastView.elapsedLabel(5, expected: 45), "About 40 seconds left")
    }

    func testPastExpectationSwitchesToLongerThanUsual() {
        XCTAssertEqual(WorkingToastView.elapsedLabel(85, expected: 85), "Taking a bit longer than usual…")
        XCTAssertEqual(WorkingToastView.elapsedLabel(120, expected: 85), "Taking a bit longer than usual…")
    }
}
