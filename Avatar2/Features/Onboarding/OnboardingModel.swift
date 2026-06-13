// Onboarding 2.0 — flow-state (Figma "Aaavatar" → Stories → Onboarding).
// E04.1 bouwt Splash + Email; `.otp` is het anker waar E04.2 (auto-verify,
// disabled-state, terug-link) op verder bouwt, de Privacy-stap (E04.3) erna.

import AvatarKit
import Foundation
import Observation

@MainActor
@Observable
final class OnboardingModel {
    enum Step: Equatable {
        case splash
        case email
        case otp
        /// E04.3: privacy/online-modellen-stap; OTP-verify én skip landen
        /// hier i.p.v. direct af te ronden.
        case privacy
    }

    private static let completedKey = "onboarding2.completed"

    static let otpLength = 6

    private(set) var step: Step = .splash
    var emailInput = ""
    var otpCode = ""
    /// Bevestiging na een geslaagde resend; gewist bij elke nieuwe actie.
    private(set) var didResendCode = false
    private(set) var hasCompleted: Bool

    let auth: AuthService

    @ObservationIgnored
    private let defaults: UserDefaults

    init(auth: AuthService, defaults: UserDefaults = .standard) {
        self.auth = auth
        self.defaults = defaults
        self.hasCompleted = defaults.bool(forKey: Self.completedKey)
    }

    /// Onboarding tonen zolang niet afgerond én niet ingelogd — een uit de
    /// Keychain herstelde sessie slaat de flow over.
    var isActive: Bool { !hasCompleted && !auth.isSignedIn }

    var trimmedEmail: String {
        emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bewust minimaal (geen RFC-regex): één `@` en een punt in het domein.
    /// Supabase doet de echte validatie; dit stuurt alleen de knop-state.
    var isEmailPlausible: Bool {
        let parts = trimmedEmail.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    var canSubmitEmail: Bool { isEmailPlausible && !auth.isBusy }

    func advanceFromSplash() {
        step = .email
    }

    func submitEmail() async {
        guard canSubmitEmail else { return }
        do {
            try await auth.requestCode(email: trimmedEmail)
            otpCode = ""
            didResendCode = false
            step = .otp
        } catch {
            // Boodschap staat in auth.lastError; de stap blijft staan.
        }
    }

    var canVerifyCode: Bool {
        otpCode.count == Self.otpLength && !auth.isBusy
    }

    /// Verifieert de code; de view triggert dit ook automatisch zodra het
    /// 6e cijfer binnen is (auto-verify). `canVerifyCode` maakt dubbele
    /// triggers (onChange + knop) onschadelijk via de isBusy-gate.
    func verifyCode() async {
        guard canVerifyCode else { return }
        didResendCode = false
        do {
            try await auth.verifyCode(email: trimmedEmail, code: otpCode)
            // E04.3: na verify naar de privacy-stap, niet meteen afronden.
            step = .privacy
        } catch {
            // Boodschap staat in auth.lastError; code blijft staan zodat
            // de gebruiker hem kan corrigeren.
        }
    }

    func resendCode() async {
        guard !auth.isBusy else { return }
        didResendCode = false
        do {
            try await auth.requestCode(email: trimmedEmail)
            otpCode = ""
            didResendCode = true
        } catch {
            // Boodschap staat in auth.lastError.
        }
    }

    /// 'Wrong email? Go back' — terug naar de e-mailstap met schone lei.
    func goBackToEmail() {
        otpCode = ""
        didResendCode = false
        step = .email
    }

    /// Continue-without-account: geen sessie, maar nog wél de privacy-stap
    /// (E04.3) — de online-modellen-keuze geldt ook anoniem.
    func skipOnboarding() {
        step = .privacy
    }

    /// E04.3: Continue op de privacy-stap rondt de onboarding af. De
    /// online-modellen-keuze is dan al naar PrivacyPreferences2 geschreven
    /// (de toggle schrijft live).
    func finishFromPrivacy() {
        markCompleted()
    }

    /// E04.2 roept dit aan na een geslaagde code-verificatie.
    func finishSignedIn() {
        markCompleted()
    }

    private func markCompleted() {
        hasCompleted = true
        defaults.set(true, forKey: Self.completedKey)
    }

    #if DEBUG
    /// Smoke-run-haak: forceer de flow open op een stap (--onboarding-step).
    func debugForce(step: Step) {
        hasCompleted = false
        self.step = step
    }
    #endif
}
