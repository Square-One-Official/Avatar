import Foundation
import AppKit

/// Dispatches `aaavatar://` URLs opened by the OS (typically via Stripe
/// Checkout return or Supabase OAuth return in the default browser).
///
/// Expected URL shapes:
///   `aaavatar://auth-callback#access_token=...&refresh_token=...`  (implicit)
///   `aaavatar://auth-callback?code=...`                             (PKCE)
///   `aaavatar://stripe-return?session_id=...`
///   `aaavatar://stripe-cancel`
@MainActor
enum URLSchemeHandler {
    static func handle(_ url: URL, appState: AppState) {
        dlog("[URLScheme] handle \(url.absoluteString)")
        guard url.scheme == "aaavatar" else {
            dlog("[URLScheme] ignored (scheme=\(url.scheme ?? "nil"))")
            return
        }
        guard let host = url.host else {
            dlog("[URLScheme] ignored (no host)")
            return
        }

        switch host {
        case "auth-callback":
            Task {
                await appState.auth.completeSignIn(from: url)
                appState.refreshEntitlement()
                NSApp.activate(ignoringOtherApps: true)
            }
        case "stripe-return":
            // Poll the backend for the webhook-updated state. If the user
            // started checkout from the Magic Cutout toggle, flip the
            // toggle on once Pro is confirmed so they land in the state
            // they originally clicked toward.
            // Dismiss whichever paywall is open — main window or settings.
            appState.showProUpgradeSheet = false
            appState.showProUpgradeSheetInSettings = false
            Task {
                // Stripe webhook usually lands in <1s, but can lag a few
                // seconds. Retry until Pro shows up or we give up — without
                // this, a slow webhook leaves the just-paid user on free
                // until the next manual refresh.
                for attempt in 0..<6 {
                    await appState.refreshEntitlementAsync()
                    if appState.proEntitlement.isPro { break }
                    if attempt < 5 {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                    }
                }
                if appState.pendingMagicCutoutEnable && appState.proEntitlement.isPro {
                    appState.magicCutoutPrefs.enabled = true
                }
                appState.pendingMagicCutoutEnable = false
            }
            NSApp.activate(ignoringOtherApps: true)
        case "stripe-cancel":
            // User cancelled checkout — leave sheet open so they can retry.
            NSApp.activate(ignoringOtherApps: true)
        default:
            break
        }
    }
}
