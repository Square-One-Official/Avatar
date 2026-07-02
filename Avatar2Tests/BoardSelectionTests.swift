// E29.4 (audit C5) — board-selectie-semantiek: shift-klik breidt een RANGE uit
// (anker→doel in board-volgorde, Finder-conventie), cmd-klik togglet, kale klik
// vervangt. De pure range-helper is hier getest; de gestures zelf zijn expliciete
// `TapGesture().modifiers(...)`-varianten (geen globale NSEvent-state meer).

import XCTest
@testable import Avatar2

final class BoardSelectionTests: XCTestCase {

    private let order = ["a", "b", "c", "d", "e"]

    func testRangeVoorwaartsVanAnkerNaarDoel() {
        let result = BoardView.rangeExtendedSelection(
            current: ["b"], anchor: "b", target: "d", order: order
        )
        XCTAssertEqual(result, ["b", "c", "d"])
    }

    func testRangeAchterwaartsWerktOok() {
        let result = BoardView.rangeExtendedSelection(
            current: ["d"], anchor: "d", target: "a", order: order
        )
        XCTAssertEqual(result, ["a", "b", "c", "d"])
    }

    func testRangeBreidtBestaandeSelectieUit() {
        // Bestaande (cmd-)selectie blijft staan; de range komt erbij (union).
        let result = BoardView.rangeExtendedSelection(
            current: ["a", "e"], anchor: "d", target: "c", order: order
        )
        XCTAssertEqual(result, ["a", "c", "d", "e"])
    }

    func testZonderAnkerIsShiftKlikAdditief() {
        let result = BoardView.rangeExtendedSelection(
            current: ["a"], anchor: nil, target: "c", order: order
        )
        XCTAssertEqual(result, ["a", "c"])
    }

    func testOnbekendAnkerValtTerugOpAdditief() {
        // Anker verwijderd uit de set (bv. node gedelete) → geen crash, additief.
        let result = BoardView.rangeExtendedSelection(
            current: ["a"], anchor: "z", target: "c", order: order
        )
        XCTAssertEqual(result, ["a", "c"])
    }

    func testAnkerIsDoelSelecteertEnkelDieNode() {
        let result = BoardView.rangeExtendedSelection(
            current: [], anchor: "c", target: "c", order: order
        )
        XCTAssertEqual(result, ["c"])
    }

    // MARK: - E47.3 — cmd-klik-toggle (de andere helft van de Finder-semantiek)

    func testToggleVoegtNodeToeEnMaaktHemAnker() {
        let result = BoardView.toggledSelection(
            current: ["a"], anchor: "a", toggling: "c"
        )
        XCTAssertEqual(result.selection, ["a", "c"])
        XCTAssertEqual(result.anchor, "c", "toegevoegde node wordt het nieuwe range-anker")
    }

    func testToggleVerwijdertNietAnkerNodeEnLaatAnkerStaan() {
        let result = BoardView.toggledSelection(
            current: ["a", "b", "c"], anchor: "a", toggling: "c"
        )
        XCTAssertEqual(result.selection, ["a", "b"])
        XCTAssertEqual(result.anchor, "a", "anker blijft staan als een ándere node uit de selectie valt")
    }

    func testToggleVerwijdertAnkerSchuiftAnkerNaarResterendeNode() {
        let result = BoardView.toggledSelection(
            current: ["a", "b"], anchor: "a", toggling: "a"
        )
        XCTAssertEqual(result.selection, ["b"])
        XCTAssertEqual(result.anchor, "b", "valt het anker zelf uit de selectie → resterende node")
    }

    func testToggleLaatsteNodeLeegtSelectieEnAnker() {
        let result = BoardView.toggledSelection(
            current: ["a"], anchor: "a", toggling: "a"
        )
        XCTAssertTrue(result.selection.isEmpty)
        XCTAssertNil(result.anchor)
    }

    func testToggleOpLegeSelectieStartNieuweSelectie() {
        let result = BoardView.toggledSelection(
            current: Set<String>(), anchor: nil, toggling: "b"
        )
        XCTAssertEqual(result.selection, ["b"])
        XCTAssertEqual(result.anchor, "b")
    }
}
