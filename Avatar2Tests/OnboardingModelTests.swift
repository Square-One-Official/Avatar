// E01.9 — unit-tests voor de OnboardingModel-flow-state (E04.1/E04.2).
// Alleen pure logica: stap-overgangen, e-mailvalidatie en completion-
// persistentie. De Supabase-paden (requestCode/verifyCode) blijven hier
// bewust buiten bereik — die vereisen netwerk en horen in een latere
// integratielaag.

import AvatarKit
import XCTest
@testable import Avatar2

@MainActor
final class OnboardingModelTests: XCTestCase {

    /// Vers model met een eigen, leeggemaakte defaults-suite per test zodat
    /// completion-state nooit tussen tests (of runs) lekt.
    private func makeModel(suite: String = #function) -> (OnboardingModel, UserDefaults) {
        let name = "nl.squareone.aaavatar2.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (OnboardingModel(auth: AuthService(), defaults: defaults), defaults)
    }

    // MARK: stap-overgangen

    func testStartsAtSplashAndAdvancesToEmail() {
        let (model, _) = makeModel()
        XCTAssertEqual(model.step, .splash)
        model.advanceFromSplash()
        XCTAssertEqual(model.step, .email)
    }

    func testGoBackToEmailClearsCodeState() {
        let (model, _) = makeModel()
        model.advanceFromSplash()
        model.otpCode = "123456"
        model.goBackToEmail()
        XCTAssertEqual(model.step, .email)
        XCTAssertEqual(model.otpCode, "")
        XCTAssertFalse(model.didResendCode)
    }

    // MARK: e-mailvalidatie (bewust minimaal — zie OnboardingModel)

    func testPlausibleEmailsPassTheGate() {
        let (model, _) = makeModel()
        for email in ["thierry@squareone.nl", "a@b.co", "x+tag@sub.domain.dev"] {
            model.emailInput = email
            XCTAssertTrue(model.isEmailPlausible, email)
        }
    }

    func testImplausibleEmailsFailTheGate() {
        let (model, _) = makeModel()
        for email in ["", "geen-apenstaart", "a@b", "a@.nl", "a@nl.", "@x.nl", "a@b@c.nl"] {
            model.emailInput = email
            XCTAssertFalse(model.isEmailPlausible, email)
        }
    }

    func testTrimmedEmailStripsWhitespace() {
        let (model, _) = makeModel()
        model.emailInput = "  thierry@squareone.nl\n"
        XCTAssertEqual(model.trimmedEmail, "thierry@squareone.nl")
        XCTAssertTrue(model.isEmailPlausible)
    }

    // MARK: code-gate

    func testCanVerifyCodeRequiresExactLength() {
        let (model, _) = makeModel()
        model.otpCode = "12345"
        XCTAssertFalse(model.canVerifyCode)
        model.otpCode = "123456"
        XCTAssertTrue(model.canVerifyCode)
        model.otpCode = "1234567"
        XCTAssertFalse(model.canVerifyCode)
    }

    // MARK: completion-persistentie

    // E04.3/E04.6: skip rondt niet meer meteen af — het pad loopt via de
    // privacy- en download-stap; pas finishFromDownload() voltooit.
    func testSkipRoutesThroughPrivacyAndDownloadThenCompletes() {
        let (model, _) = makeModel()
        XCTAssertFalse(model.hasCompleted)
        model.skipOnboarding()
        XCTAssertEqual(model.step, .privacy)
        XCTAssertFalse(model.hasCompleted)
        XCTAssertTrue(model.isActive)
        model.finishFromPrivacy()
        XCTAssertEqual(model.step, .download)
        XCTAssertFalse(model.hasCompleted)
        model.finishFromDownload()
        XCTAssertTrue(model.hasCompleted)
        XCTAssertFalse(model.isActive)
    }

    func testCompletionPersistsAcrossModelInstances() {
        let (model, defaults) = makeModel()
        model.skipOnboarding()
        model.finishFromPrivacy()
        model.finishFromDownload()
        let revived = OnboardingModel(auth: AuthService(), defaults: defaults)
        XCTAssertTrue(revived.hasCompleted)
    }

    func testFinishSignedInMarksCompleted() {
        let (model, _) = makeModel()
        model.finishSignedIn()
        XCTAssertTrue(model.hasCompleted)
    }
}
