import Foundation
import Observation
import Supabase

/// Auth 2.0: e-mail + zescijferige code (Supabase OTP). Geen OAuth, geen
/// PKCE, geen deep-links — de hele flow blijft in de app. De Google-infra
/// van v1 blijft serverzijde bestaan; een OTP-login op het e-mailadres van
/// een bestaande Google-user resolveert naar dezelfde Supabase-user, dus
/// Stripe/Pro blijft hangen aan dezelfde user-id (identiteitstest: E01.7).
///
/// Flow:
///   1. `requestCode(email:)` → Supabase mailt een `{{ .Token }}`-code.
///   2. `verifyCode(email:code:)` → sessie; `accessToken`/`email` flippen
///      direct zodat de UI niet op de async `authStateChanges`-stream hoeft
///      te wachten (zelfde race-les als v1's `completeSignIn`).
@MainActor
@Observable
public final class AuthService {
    /// Current Supabase access token (JWT) or nil when signed out.
    public private(set) var accessToken: String?
    /// Display identity for the Settings UI.
    public private(set) var email: String?
    /// True terwijl een code-aanvraag of verificatie loopt.
    public private(set) var isBusy = false
    /// Laatste auth-fout voor de UI; gewist bij elke nieuwe poging.
    public private(set) var lastError: String?

    public var isSignedIn: Bool { accessToken != nil }

    /// The shared Supabase client. Exposed zodat andere services (bv. een
    /// toekomstige realtime-feature) dezelfde sessiestore hergebruiken.
    @ObservationIgnored
    public let supabase: SupabaseClient

    @ObservationIgnored
    private var authStateTask: Task<Void, Never>?

    public init() {
        // flowType .implicit: OTP-verify heeft geen PKCE-verifier nodig en
        // dit houdt de client compatibel met server-geïnitieerde links
        // (zelfde overweging als v1's AuthManager).
        self.supabase = SupabaseClient(
            supabaseURL: SupabaseConfiguration.url,
            supabaseKey: SupabaseConfiguration.publishableKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: AuthSessionFileStorage(),
                    flowType: .implicit
                )
            )
        )
        observeAuthState()
    }

    deinit {
        authStateTask?.cancel()
    }

    /// Stap 1: vraag een e-mailcode aan. `shouldCreateUser: true` zodat een
    /// nieuw adres direct een account wordt (geen aparte sign-up-flow).
    public func requestCode(email: String) async throws {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            try await supabase.auth.signInWithOTP(email: email, shouldCreateUser: true)
        } catch {
            lastError = friendlyMessage(error)
            throw error
        }
    }

    /// Stap 2: verifieer de code. Spiegelt de sessie eager naar
    /// `accessToken`/`email`.
    ///
    /// `signInWithOTP(shouldCreateUser: true)` levert voor een BESTAANDE
    /// gebruiker een `.email`-OTP, maar voor een NIEUW adres een
    /// `.signup`-token. Dezelfde 6-cijfercode met het verkeerde type geeft
    /// "Token has expired or is invalid" — daarom proberen we eerst `.email`
    /// en vallen we terug op `.signup` (E18.21).
    public func verifyCode(email: String, code: String) async throws {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            try await verifySession(email: email, code: code, type: .email)
        } catch {
            do {
                try await verifySession(email: email, code: code, type: .signup)
            } catch {
                lastError = friendlyMessage(error)
                throw error
            }
        }
    }

    private func verifySession(email: String, code: String, type: EmailOTPType) async throws {
        let response = try await supabase.auth.verifyOTP(email: email, token: code, type: type)
        if let session = response.session {
            accessToken = session.accessToken
            self.email = session.user.email
        }
    }

    /// Wist de laatste foutmelding (bv. nadat de toast 'm getoond heeft).
    public func clearError() {
        lastError = nil
    }

    public func signOut() {
        Task {
            try? await supabase.auth.signOut()
        }
    }

    // MARK: - Internal

    /// Houd `accessToken`/`email` in sync over launches, token-refreshes en
    /// sign-outs heen.
    private func observeAuthState() {
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (_, session) in self.supabase.auth.authStateChanges {
                await MainActor.run {
                    self.accessToken = session?.accessToken
                    self.email = session?.user.email
                }
            }
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

extension AuthService: AccessTokenProviding {}
