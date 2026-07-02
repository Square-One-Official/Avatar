// E05.3 — canvasstates van de import/isolating-flow. De engine-paden zelf
// zijn in AvatarKit getest (E02.1); hier alleen de state-overgangen die
// zonder echte foto te raken zijn.

import AvatarKit
import XCTest
@testable import Avatar2

@MainActor
final class ShellModelTests: XCTestCase {

    func testStartLeeg() {
        let model = ShellModel(entitlement: EntitlementModel(auth: AuthService()))
        if case .empty = model.canvas {} else {
            XCTFail("verwacht .empty als startstaat")
        }
    }

    func testOnleesbareDataGaatNaarFailed() async {
        let model = ShellModel(entitlement: EntitlementModel(auth: AuthService()))
        await model.importImage(data: Data([0x00, 0x01, 0x02]))
        if case .failed = model.canvas {} else {
            XCTFail("verwacht .failed bij onleesbare data")
        }
    }

    // MARK: - E36.5 (audit-B5): bestandsnaam → default-portretnaam

    func testDefaultNaamHumaniseertKoppeltekensEnUnderscores() {
        let url = URL(fileURLWithPath: "/tmp/p1-man_beard.png")
        XCTAssertEqual(ShellModel.defaultPortraitName(from: url), "p1 man beard")
    }

    func testDefaultNaamStriptAlleenDeLaatsteExtensie() {
        let url = URL(fileURLWithPath: "/Users/x/Photos/team.profile.jpeg")
        XCTAssertEqual(ShellModel.defaultPortraitName(from: url), "team.profile")
    }

    func testDefaultNaamVouwtDubbeleSeparatorsSamen() {
        let url = URL(fileURLWithPath: "/tmp/anna--de_-winter.HEIC")
        XCTAssertEqual(ShellModel.defaultPortraitName(from: url), "anna de winter")
    }

    func testDefaultNaamBlijftIntactZonderSeparators() {
        let url = URL(fileURLWithPath: "/tmp/Portrait.png")
        XCTAssertEqual(ShellModel.defaultPortraitName(from: url), "Portrait")
    }
}
