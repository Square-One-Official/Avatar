import Foundation

/// Free-tier ceilings the rest of the app gates against. Exceeding either
/// triggers a Pro upsell — a soft toast for the batch ceiling, the paywall
/// sheet for the library ceiling. Pro users have no enforced limits beyond
/// the batch-confirm threshold in `BatchConfirmRequest.threshold`.
enum FreeTier {
    /// Lifetime free imports a free account may run. Splits into 3 AI
    /// (Magic Cutout trial) + 3 basic (Subject Lift) imports — see
    /// `freeMagicCutoutAllowance` for the AI portion. Enforced
    /// server-side via `users.free_imports_used` AND
    /// `device_imports.free_imports_used` (Keychain UUID). Deleting a
    /// portrait does NOT free a slot — otherwise the cap is trivially
    /// defeated by import-then-delete. Bump this only after
    /// re-evaluating the trial economics.
    /// Mirrors `FREE_IMPORTS_ALLOWANCE` in `backend/lib/supabase.ts`.
    static let maxPortraits = 6

    /// Maximum number of images a free user can drop / pick in a single
    /// import. Two is enough to feel useful (couple shot, before/after) but
    /// low enough that "import a folder of 30 headshots" reads as a Pro perk.
    /// Pro users are still subject to `BatchConfirmRequest.threshold`.
    static let maxBatchImport = 2

    /// Free Magic Cutout trial allowance — number of cloud cutouts a free
    /// user may run before the toggle is gated. Mirrors the backend constant
    /// `FREE_CUTOUTS_ALLOWANCE` in `lib/supabase.ts`. Used only for copy /
    /// progress UI; server is the actual gate. Reverse-trial pattern:
    /// experience the premium model first, then drop to the basic
    /// (Subject Lift) for the remaining 3 imports.
    static let freeMagicCutoutAllowance = 3
}

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

/// Pro subscription tier. Backend is source of truth — the raw value
/// matches the `tier` column in Supabase.
///
/// We collapsed the previous Starter/Plus/Studio ladder to a single Pro
/// tier when Magic Cutout shipped: one price point (€4,99 / 200 credits)
/// is easier to communicate than three. Power users top up with the
/// `CreditPack` enum below instead of climbing tiers.
enum ProTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case pro

    var id: String { rawValue }

    var displayName: String { "Pro" }

    /// Monthly credit grant, mirrored server-side. Magic Cutout costs 1
    /// credit per image.
    var monthlyCredits: Int { 200 }

    /// Display price in EUR (informational only — Stripe is source of truth).
    var monthlyPriceEUR: String { "€4,99" }

    /// Display price for the yearly plan (€49,90 = 10× monthly = 2 months
    /// free, 17% discount). Stripe is source of truth.
    var annualPriceEUR: String { "€49,90" }

    /// Per-month equivalent when billed annually, for "€4,16/mo billed
    /// annually" copy in the paywall.
    var annualPricePerMonthEUR: String { "€4,16" }
}

/// Billing cadence chosen by the user in the paywall. Sent to the
/// backend on `/v1/checkout/subscribe` to route to the right Stripe
/// price ID. Default in-app is `.year` so the better value is anchored.
enum SubscriptionInterval: String, Codable, CaseIterable, Identifiable, Sendable {
    case month
    case year

    var id: String { rawValue }
}

/// One-time credit pack the user can buy on top of (or instead of) a
/// subscription. Topped-up credits never expire and stack with the
/// monthly grant. Raw value matches the Stripe price lookup key.
///
/// Pricing ladder uses the decoy effect — bigger pack = better value
/// per credit. The middle pack (`credits200`) anchors; `credits750`
/// makes it look reasonable; `credits50` removes the impulse barrier.
enum CreditPack: String, Codable, CaseIterable, Identifiable, Sendable {
    case credits50
    case credits200
    case credits750

    var id: String { rawValue }

    /// Number of credits added to the user's balance after a successful
    /// purchase. Source of truth is server-side; this is for UI only.
    var credits: Int {
        switch self {
        case .credits50: return 50
        case .credits200: return 200
        case .credits750: return 750
        }
    }

    /// Display price in EUR. Stripe is source of truth.
    var priceEUR: String {
        switch self {
        case .credits50: return "€1,99"
        case .credits200: return "€4,99"
        case .credits750: return "€14,99"
        }
    }

    /// Cents per credit, used for the "best value" calculation in the
    /// paywall. Lower = better deal. Pure UI math; never sent to server.
    var centsPerCredit: Double {
        switch self {
        case .credits50: return 199.0 / 50.0   // 3.98¢
        case .credits200: return 499.0 / 200.0 // 2.50¢
        case .credits750: return 1499.0 / 750.0 // 2.00¢ — anchor
        }
    }

    /// True for the pack with the best per-credit price — drives the
    /// "BESTE WAARDE" badge in the paywall.
    var isBestValue: Bool {
        self == .credits750
    }

    /// Stable display order in the paywall, smallest → largest. Matches
    /// the decoy reading direction (impulse → anchor).
    static var displayOrder: [CreditPack] {
        [.credits50, .credits200, .credits750]
    }
}

/// Subscription lifecycle as reported by the backend on `GET /v1/account`.
enum SubscriptionStatus: String, Codable, Sendable {
    case active
    case lapsed
    case none
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
    /// Magic Cutout free-trial calls the user has spent. Server is source
    /// of truth — see `users.free_cutouts_used`. Survives reinstall.
    var freeCutoutsUsed: Int = 0
    /// Free-trial calls still available (server-clamped to 0…allowance).
    var freeCutoutsRemaining: Int = 0
    /// Lifetime imports the user has run (Subject Lift OR Magic Cutout).
    /// Server-tracked across `users.free_imports_used` AND
    /// `device_imports.free_imports_used`. Used for the sidebar quota card
    /// and the empty-state import gate.
    var freeImportsUsed: Int = 0
    /// Imports remaining before the free tier is exhausted. We surface the
    /// minimum of the user-counter and device-counter remainings — the
    /// server returns whichever is more restrictive.
    var freeImportsRemaining: Int = FreeTier.maxPortraits

    var isPro: Bool { tier != nil }
    var hasCredits: Bool { credits > 0 }
    /// True when the user can run a Magic Cutout: either they're Pro, or
    /// they still have free-trial calls left. Drives the dropzone toggle
    /// state and `ImportFlow.shouldUseMagicCutout`.
    var canUseProCutout: Bool { isPro || freeCutoutsRemaining > 0 }
    /// True when a free user has at least one import slot left — Pro users
    /// are unlimited. UI gates against this instead of the library count.
    var canImport: Bool { isPro || freeImportsRemaining > 0 }

    /// Free imports the user has remaining of the BASIC (Subject Lift)
    /// portion of the trial. Computed from total remaining minus AI
    /// remaining, clamped to [0, 3]. Drives the second dot-row in
    /// `SidebarProQuotaCard` so users see the two phases of free.
    var freeBasicImportsRemaining: Int {
        let basicAllowance = max(0, FreeTier.maxPortraits - FreeTier.freeMagicCutoutAllowance)
        let aiRemaining = freeCutoutsRemaining
        // Total free imports left = the import-counter remaining; basic
        // = total - AI (clamped to the basic allowance).
        let basicLeft = freeImportsRemaining - aiRemaining
        return min(basicAllowance, max(0, basicLeft))
    }

    /// Resets all state (e.g. on sign-out). Free-trial counters reset to
    /// the full allowance — but they're rehydrated from /v1/account the
    /// moment the next import-claim or sign-in happens, so the device
    /// counter still gates a logged-out cheat attempt.
    func clear() {
        tier = nil
        credits = 0
        monthlyQuota = 0
        monthlyResetAt = nil
        subscriptionStatus = .none
        subscriptionRenewsAt = nil
        freeCutoutsUsed = 0
        freeCutoutsRemaining = 0
        freeImportsUsed = 0
        freeImportsRemaining = FreeTier.maxPortraits
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
        freeCutoutsUsed = payload.freeCutoutsUsed ?? 0
        freeCutoutsRemaining = payload.freeCutoutsRemaining ?? 0
        freeImportsUsed = payload.freeImportsUsed ?? 0
        freeImportsRemaining = payload.freeImportsRemaining ?? FreeTier.maxPortraits
        lastError = nil
    }
}

/// Server payload for `GET /v1/account`. JSON keys are snake_case; the
/// `BackendClient` decoder applies `.convertFromSnakeCase`, so e.g.
/// `credits_remaining` → `creditsRemaining`.
///
/// `freeCutoutsUsed` / `freeCutoutsRemaining` are optional so older
/// backends (pre-migration 003) keep decoding cleanly.
struct AccountPayload: Codable, Sendable {
    let tier: ProTier?
    let creditsRemaining: Int
    let monthlyQuota: Int
    let monthlyResetAt: Date?
    let subscriptionStatus: SubscriptionStatus
    let subscriptionRenewsAt: Date?
    let freeCutoutsUsed: Int?
    let freeCutoutsRemaining: Int?
    let freeImportsUsed: Int?
    let freeImportsRemaining: Int?
}
