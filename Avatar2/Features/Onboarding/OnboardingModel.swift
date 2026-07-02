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
        /// E04.6: optionele high-fidelity-model-download (skipbaar,
        /// achtergrond). Komt na privacy.
        case download
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

    /// Onboarding tonen zolang niet afgerond. Een uit de Keychain herstelde
    /// sessie (flow nog op splash) slaat de flow over, maar een sign-in
    /// mídden in de flow (`verifyCode` → `.privacy`) mag de flow niet
    /// unmounten: anders verliest het ingelogde pad de privacy- (E04.3) en
    /// downloadstap (E04.6) — audit B4/E04.8.
    var isActive: Bool {
        guard !hasCompleted else { return false }
        return step != .splash || !auth.isSignedIn
    }

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
            // `isActive` blijft true (stap != .splash) ook al flipt
            // `auth.isSignedIn` in hetzelfde frame — E04.8.
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

    /// E04.3 → E04.6: Continue op de privacy-stap gaat naar de optionele
    /// download-stap. De online-modellen-keuze is dan al weggeschreven.
    func finishFromPrivacy() {
        step = .download
    }

    /// E04.6: Continue/skip op de download-stap rondt de onboarding af. Een
    /// gestarte download loopt door in de achtergrond (OrmbgModelStore is
    /// een actor; voortgang blijft zichtbaar in Settings > AI & Models).
    func finishFromDownload() {
        markCompleted()
    }

    /// E04.8: sign-out vanuit de Shell. Wordt de onboarding daarna weer
    /// actief (`hasCompleted == false`), dan begint die op splash — niet op
    /// een verweesde tussenstap zoals `.privacy`.
    func resetToSplash() {
        emailInput = ""
        otpCode = ""
        didResendCode = false
        step = .splash
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
