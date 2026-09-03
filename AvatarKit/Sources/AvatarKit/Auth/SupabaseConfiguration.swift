import Foundation

/// Static configuration for the Supabase-backed Pro stack (2.0).
/// URL and publishable key are safe to ship inside the client binary — the
/// publishable key is the read-only anon-equivalent under RLS, not a secret.
/// Zelfde project als v1 (`SupabaseConfig` in Avatar/): OTP-login op het
/// e-mailadres van een bestaande Google-user levert dezelfde Supabase-user
/// op, dus Pro blijft behouden (identiteitstest: E01.7).
public enum SupabaseConfiguration {
    public static let url = URL(string: "https://acmnyvdzjxayynmtnsav.supabase.co")!
    public static let publishableKey = "sb_publishable_eW5edOEumcjLO1l_4UFdgQ_cfau6krh"
}
