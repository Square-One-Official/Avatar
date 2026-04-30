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
                await appState.refreshEntitlementAsync()
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
