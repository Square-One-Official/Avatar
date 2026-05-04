import Foundation
import AppKit
import Supabase
import Auth

/// Thin wrapper around `SupabaseClient.auth`. Owns the single `SupabaseClient`
/// used by the app, exposes a minimal, observable surface for views, and
/// keeps the synchronous `accessToken` / `email` / `isSignedIn` fields that
/// `BackendClient` and the Settings UI read. Sessions persist in a sandboxed
/// file via `FileAuthStorage` — Keychain ACLs are tied to the binary's code
/// signature, so every release would otherwise re-prompt "Always Allow"
/// multiple times per launch.
@MainActor
@Observable
final class AuthManager {
    /// Current Supabase access token (JWT) or nil when signed out.
    private(set) var accessToken: String?
    /// Display identity for the Settings UI.
    private(set) var email: String?
    /// True while an OAuth round-trip is in flight.
    var isSigningIn: Bool = false
    /// Last sign-in failure surfaced to the UI. Cleared when a sign-in
    /// attempt starts. Settings reads this so the user sees *why* clicking
    /// "Open Avatar" from the browser didn't sign them in (instead of the
    /// silent regression where they'd land back on the signed-out card with
    /// no feedback).
    private(set) var lastSignInError: String?

    var isSignedIn: Bool { accessToken != nil }

    /// The shared Supabase client. Exposed so other services (e.g. the
    /// BackendClient fallback paths, or future realtime features) can reuse
    /// the same session store instead of instantiating their own.
    @ObservationIgnored
    let supabase: SupabaseClient

    @ObservationIgnored
    private var authStateTask: Task<Void, Never>?

    init() {
        // flowType: .implicit — Supabase magic-links generated server-side
        // by `signInWithOtp` produce `#access_token=...` callback URLs.
        // PKCE (the SDK default) requires a client-generated verifier, which
        // a server-initiated email link can't carry, so `session(from:)`
        // would reject the fragment with "Not a valid PKCE flow URL". OAuth
        // works under either flow; switching the whole client to implicit
        // keeps both code paths on the same parser.
        self.supabase = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.publishableKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: FileAuthStorage(),
                    flowType: .implicit
                )
            )
        )
        observeAuthState()
    }

    deinit {
        authStateTask?.cancel()
    }

    /// Opens Google OAuth in the user's default browser. The browser will
    /// redirect back to `aaavatar://auth-callback?...` which the URL scheme
    /// handler forwards to `completeSignIn(from:)`.
    func startSignIn() {
        isSigningIn = true
        lastSignInError = nil
        do {
            let url = try supabase.auth.getOAuthSignInURL(
                provider: .google,
                redirectTo: SupabaseConfig.authRedirectURL,
            )
            NSWorkspace.shared.open(url)
        } catch {
            dlog("[Auth] getOAuthSignInURL failed: \(error)")
            lastSignInError = error.localizedDescription
            isSigningIn = false
        }
    }

    /// Called by the URL scheme handler when the browser returns with an
    /// OAuth code or fragment. Exchanges it for a session and persists it.
    /// Eagerly mirrors the new session into `accessToken`/`email` so the UI
    /// flips immediately — without this, we relied on the `authStateChanges`
    /// async stream, and races there left users stuck on the signed-out card
    /// after clicking "Open Avatar" from the browser.
    func completeSignIn(from url: URL) async {
        defer { isSigningIn = false }
        dlog("[Auth] completeSignIn from \(url.absoluteString)")
        do {
            let session = try await supabase.auth.session(from: url)
            accessToken = session.accessToken
            email = session.user.email
            lastSignInError = nil
            dlog("[Auth] sign-in succeeded for \(session.user.email ?? "<no email>")")
        } catch {
            dlog("[Auth] session(from:) failed: \(error)")
            lastSignInError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    func signOut() {
        Task {
            try? await supabase.auth.signOut()
        }
    }

    // MARK: - Internal

    /// Subscribe to Supabase auth events so `accessToken` / `email` stay in
    /// sync across launches, token refreshes, and sign-outs.
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
}
