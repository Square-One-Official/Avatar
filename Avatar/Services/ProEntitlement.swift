import AvatarKit
import Foundation

// FreeTier, ProTier, SubscriptionInterval, CreditPack, SubscriptionStatus en
// AccountPayload zijn verhuisd naar AvatarKit (E01.5) — zie
// AvatarKit/Sources/AvatarKit/Backend/EntitlementModels.swift.

/// Hard ceilings that apply to Pro users. These are technical/safety
/// limits, not upsell gates — Pro users hitting them get an informational
/// toast (no Upgrade CTA), since they're already paying.
enum ProLimits {
    /// Hard cap on photos per single import. Each in-flight cutout decode
    /// peaks ~120-150 MB on a 4K photo and the pipeline runs without a
    /// concurrency throttle, so an unbounded drop of "300 photos" can trash
    /// 8-16 GB Macs. 15 keeps the worst-case RSS in check while still
    /// reading as "import a folder" to the user. Bump this only after
    /// adding a semaphore to `PortraitDropHandler.processAll`.
    static let maxBatchImport = 15
}

/// Observable Pro/credits state. Populated by `BackendClient.me()` on launch,
/// after checkout return, and when a 402 is received from the backend.
@MainActor
@Observable
final class ProEntitlement {
    /// Active tier, or nil when the user has no subscription.
    var tier: ProTier?
    /// Credits remaining (monthly grant + unspent top-ups, server-aggregated).
    var credits: Int = 0
    /// Monthly grant for the active tier (e.g. 200 for Pro). 0 when free.
    var monthlyQuota: Int = 0
    /// When the monthly credit grant resets. UI label: "credits renew at".
    var monthlyResetAt: Date?
    /// Subscription state. `.active` = paid; `.lapsed` = past-due / cancelled
    /// but still in grace; `.none` = never subscribed or fully cancelled.
    var subscriptionStatus: SubscriptionStatus = .none
    /// When the subscription auto-renews (or the access window ends if lapsed).
    /// Distinct from `monthlyResetAt` because for Pro both happen monthly but
    /// can drift: monthly grant resets on the calendar month, subscription
    /// renews on the anniversary date.
    var subscriptionRenewsAt: Date?
    /// Whether a refresh request is in flight.
    var isRefreshing: Bool = false
    /// Last error message from a refresh attempt.
    var lastError: String?
    /// Lifetime imports the user has run (Subject Lift OR Magic Cutout —
    /// both count the same against the unified `FreeTier.maxPortraits`
    /// cap). Server-tracked across `users.free_imports_used` AND
    /// `device_imports.free_imports_used`. Used for the sidebar quota card
    /// and the empty-state import gate.
    var freeImportsUsed: Int = 0
    /// Imports remaining before the free tier is exhausted. We surface the
    /// minimum of the user-counter and device-counter remainings — the
    /// server returns whichever is more restrictive.
    var freeImportsRemaining: Int = FreeTier.maxPortraits
    /// True when this Mac is Pro because of a pre-auth checkout (the
    /// `device_grants` row matches), but the user is not signed in. Drives
    /// the "Sync across Macs" banner in Settings + sidebar.
    var needsAccountLink: Bool = false
    /// Email captured by Stripe at checkout. Shown in the sync banner so
    /// the user knows which inbox to check after tapping "Email me a
    /// sign-in link". Nil for signed-in users (we already have their email
    /// via AuthManager).
    var linkEmail: String?

    var isPro: Bool { tier != nil }
    var hasCredits: Bool { credits > 0 }
    /// True when the user can run a Magic Cutout: either they're Pro, or
    /// they still have free import slots left (any of the 3 free portraits
    /// may be spent on cloud AI). Drives the dropzone toggle state and
    /// `ImportFlow.shouldUseMagicCutout`.
    var canUseProCutout: Bool { isPro || freeImportsRemaining > 0 }
    /// True when a free user has at least one import slot left — Pro users
    /// are unlimited. UI gates against this instead of the library count.
    var canImport: Bool { isPro || freeImportsRemaining > 0 }

    /// Resets all state (e.g. on sign-out). `freeImportsRemaining` resets
    /// to the full allowance — but it's rehydrated from /v1/account the
    /// moment the next import-claim or sign-in happens, so the device
    /// counter still gates a logged-out cheat attempt.
    func clear() {
        tier = nil
        credits = 0
        monthlyQuota = 0
        monthlyResetAt = nil
        subscriptionStatus = .none
        subscriptionRenewsAt = nil
        freeImportsUsed = 0
        freeImportsRemaining = FreeTier.maxPortraits
        needsAccountLink = false
        linkEmail = nil
        lastError = nil
    }

    /// Replace state from a server payload.
    func apply(_ payload: AccountPayload) {
        tier = payload.tier
        credits = payload.creditsRemaining
        monthlyQuota = payload.monthlyQuota
        monthlyResetAt = payload.monthlyResetAt
        subscriptionStatus = payload.subscriptionStatus
        subscriptionRenewsAt = payload.subscriptionRenewsAt
        freeImportsUsed = payload.freeImportsUsed ?? 0
        freeImportsRemaining = payload.freeImportsRemaining ?? FreeTier.maxPortraits
        needsAccountLink = payload.needsAccountLink ?? false
        linkEmail = payload.linkEmail
        lastError = nil
    }
}
