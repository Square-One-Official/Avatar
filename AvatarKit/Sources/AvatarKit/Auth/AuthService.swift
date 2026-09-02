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

    /// Wordt aangeroepen zodra een sessie async hersteld wordt (nil → token).
    /// EntitlementModel hangt hieraan om /v1/account opnieuw te fetchen —
    /// `.onChange(of: isSignedIn)` op een computed property via een nested
    /// @Observable triggert niet betrouwbaar bij launch.
    public var onSignedIn: (@MainActor () -> Void)?

    /// The shared Supabase client. Exposed zodat andere services (bv. een
    /// toekomstige realtime-feature) dezelfde sessiestore hergebruiken.
    @ObservationIgnored
    public let supabase: SupabaseClient

    @ObservationIgnored
    private var authStateTask: Task<Void, Never>?

    /// - Parameter storage: waar de Supabase-sessie leeft. Default is het
    ///   versleutelde bestand in de app-container. Tests en smokes geven
    ///   `AuthSessionMemoryStorage()` mee: de unit-test-host draait in
    ///   dezelfde container als de echte app, en een `signOut()` op de
    ///   file-storage wist dan het echte sessiebestand én trekt via
    ///   `/logout?scope=global` alle refresh-tokens van de user in.
    public init(storage: any AuthLocalStorage = AuthSessionFileStorage()) {
        // flowType .implicit: OTP-verify heeft geen PKCE-verifier nodig en
        // dit houdt de client compatibel met server-geïnitieerde links
        // (zelfde overweging als v1's AuthManager).
        self.supabase = SupabaseClient(
            supabaseURL: SupabaseConfiguration.url,
            supabaseKey: SupabaseConfiguration.publishableKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: storage,
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
    /// `signInWithOTP` levert een email-OTP die met type `.email` geverifieerd
    /// wordt (zowel voor nieuwe als bestaande adressen in moderne Supabase).
    /// We doen één poging: een tweede poging met een ander type zou de
    /// single-use token kunnen verbruiken en alsnog "expired" geven. Faalt het
    /// hier, dan ligt de oorzaak serverzijde (e-mailtemplate met magic-link die
    /// door een mailclient ge-prefetcht wordt, of een te korte OTP-expiry) —
    /// zie plan/DECISIONS-PENDING.md. De ruwe fout gaat naar `lastError` zodat
    /// de UI 'm in een toast kan tonen.
    public func verifyCode(email: String, code: String) async throws {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let response = try await supabase.auth.verifyOTP(email: email, token: code, type: .email)
            if let session = response.session {
                let hadToken = accessToken != nil
                accessToken = session.accessToken
                self.email = session.user.email
                if !hadToken && accessToken != nil {
                    onSignedIn?()
                }
            }
        } catch {
            lastError = friendlyMessage(error)
            throw error
        }
    }

    /// Wist de laatste foutmelding (bv. nadat de toast 'm getoond heeft).
    public func clearError() {
        lastError = nil
    }

    #if DEBUG
    /// Test-seam (E04.8): laat unit-tests een sessie simuleren zonder
    /// Supabase-netwerk — spiegelt alleen de eager-flip van `verifyCode`/
    /// `signOut`. Alleen in DEBUG-builds aanwezig.
    public func debugSetSession(accessToken: String?, email: String? = nil) {
        self.accessToken = accessToken
        self.email = email
    }
    #endif

    public func signOut() {
        // Eager-clear, spiegelt de eager-flip in `verifyCode`: de UI reflecteert
        // direct "uitgelogd" i.p.v. te wachten op de async `authStateChanges`-
        // stream (zelfde race-les). De stream bevestigt het daarna idempotent.
        accessToken = nil
        email = nil
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
                    let hadToken = self.accessToken != nil
                    self.accessToken = session?.accessToken
                    self.email = session?.user.email
                    let hasToken = self.accessToken != nil
                    if !hadToken && hasToken {
                        self.onSignedIn?()
                    }
                }
            }
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

extension AuthService: AccessTokenProviding {}
