import Foundation

/// Static configuration for the Supabase-backed Pro stack.
/// URL and publishable key are safe to ship inside the client binary — the
/// publishable key is the read-only anon-equivalent under RLS, not a secret.
enum SupabaseConfig {
    static let url = URL(string: "https://acmnyvdzjxayynmtnsav.supabase.co")!
    static let publishableKey = "sb_publishable_eW5edOEumcjLO1l_4UFdgQ_cfau6krh"

    /// Web bridge page Supabase redirects to once Google sign-in completes
    /// in the default browser. The page forwards the same query + fragment
    /// to `aaavatar://auth-callback` (handled by `URLSchemeHandler`) and then
    /// shows a "you can close this tab" message — without it the browser tab
    /// is left dangling on a blank Supabase page after the OS hands off to
    /// the app, which users read as "did sign-in actually work?".
    ///
    /// This URL must be present in Supabase Auth → URL Configuration →
    /// Redirect URLs. Source for the page: `backend/api/auth-callback.ts`.
    static let authRedirectURL = URL(string: "https://api.aaavatar.nl/auth-callback")!
}
