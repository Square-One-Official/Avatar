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
    }

    private static let completedKey = "onboarding2.completed"

    private(set) var step: Step = .splash
    var emailInput = ""
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
            step = .otp
        } catch {
            // Boodschap staat in auth.lastError; de stap blijft staan.
        }
    }

    /// Continue-without-account: app in zonder sessie; inloggen kan later
    /// alsnog via Settings.
    func skipOnboarding() {
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
}
