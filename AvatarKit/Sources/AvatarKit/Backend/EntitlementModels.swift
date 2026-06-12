import Foundation

/// Free-tier ceilings the rest of the app gates against. Exceeding either
/// triggers a Pro upsell — a soft toast for the batch ceiling, the paywall
/// sheet for the library ceiling. Pro users have no enforced limits beyond
/// the batch-confirm threshold in `BatchConfirmRequest.threshold`.
public enum FreeTier {
    /// Lifetime free imports a free account may run. Source-agnostic — a
    /// slot is spent whether the user runs Magic Cutout (cloud) or Subject
    /// Lift (local). Enforced server-side via `users.free_imports_used`
    /// AND `device_imports.free_imports_used` (Keychain UUID, anchors to
    /// first launch). Deleting a portrait does NOT free a slot —
    /// otherwise the cap is trivially defeated by import-then-delete.
    /// Mirrors `FREE_IMPORTS_ALLOWANCE` in `backend/lib/supabase.ts`.
    public static let maxPortraits = 3
}

/// Pro subscription tier. Backend is source of truth — the raw value
/// matches the `tier` column in Supabase.
///
/// We collapsed the previous Starter/Plus/Studio ladder to a single Pro
/// tier when Magic Cutout shipped: one price point (€4,99 / 200 credits)
/// is easier to communicate than three. Power users top up with the
/// `CreditPack` enum below instead of climbing tiers.
public enum ProTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case pro

    public var id: String { rawValue }

    public var displayName: String { "Pro" }

    /// Monthly credit grant, mirrored server-side. Magic Cutout costs 1
    /// credit per image.
    public var monthlyCredits: Int { 200 }

    /// Display price in EUR (informational only — Stripe is source of truth).
    public var monthlyPriceEUR: String { "€4,99" }

    /// Display price for the yearly plan (€49,90 = 10× monthly = 2 months
    /// free, 17% discount). Stripe is source of truth.
    public var annualPriceEUR: String { "€49,90" }

    /// Per-month equivalent when billed annually, for "€4,16/mo billed
    /// annually" copy in the paywall.
    public var annualPricePerMonthEUR: String { "€4,16" }
}

/// Billing cadence chosen by the user in the paywall. Sent to the
/// backend on `/v1/checkout/subscribe` to route to the right Stripe
/// price ID. Default in-app is `.year` so the better value is anchored.
public enum SubscriptionInterval: String, Codable, CaseIterable, Identifiable, Sendable {
    case month
    case year

    public var id: String { rawValue }
}

/// One-time credit pack the user can buy on top of (or instead of) a
/// subscription. Topped-up credits never expire and stack with the
/// monthly grant. Raw value matches the Stripe price lookup key.
///
/// Pricing ladder uses the decoy effect — bigger pack = better value
/// per credit. The middle pack (`credits200`) anchors; `credits750`
/// makes it look reasonable; `credits50` removes the impulse barrier.
public enum CreditPack: String, Codable, CaseIterable, Identifiable, Sendable {
    case credits50
    case credits200
    case credits750

    public var id: String { rawValue }

    /// Number of credits added to the user's balance after a successful
    /// purchase. Source of truth is server-side; this is for UI only.
    public var credits: Int {
        switch self {
        case .credits50: return 50
        case .credits200: return 200
        case .credits750: return 750
        }
    }

    /// Display price in EUR. Stripe is source of truth.
    public var priceEUR: String {
        switch self {
        case .credits50: return "€1,99"
        case .credits200: return "€4,99"
        case .credits750: return "€14,99"
        }
    }

    /// Cents per credit, used for the "best value" calculation in the
    /// paywall. Lower = better deal. Pure UI math; never sent to server.
    public var centsPerCredit: Double {
        switch self {
        case .credits50: return 199.0 / 50.0   // 3.98¢
        case .credits200: return 499.0 / 200.0 // 2.50¢
        case .credits750: return 1499.0 / 750.0 // 2.00¢ — anchor
        }
    }

    /// True for the pack with the best per-credit price — drives the
    /// "BESTE WAARDE" badge in the paywall.
    public var isBestValue: Bool {
        self == .credits750
    }

    /// Stable display order in the paywall, smallest → largest. Matches
    /// the decoy reading direction (impulse → anchor).
    public static var displayOrder: [CreditPack] {
        [.credits50, .credits200, .credits750]
    }
}

/// Subscription lifecycle as reported by the backend on `GET /v1/account`.
public enum SubscriptionStatus: String, Codable, Sendable {
    case active
    case lapsed
    case none
}

/// Server payload for `GET /v1/account`. JSON keys are snake_case; the
/// `BackendClient` decoder applies `.convertFromSnakeCase`, so e.g.
/// `credits_remaining` → `creditsRemaining`.
///
/// `freeCutoutsUsed` / `freeCutoutsRemaining` are still emitted by the
/// backend for protocol stability but no longer surfaced — the unified
/// free counter is `freeImportsRemaining`.
public struct AccountPayload: Codable, Sendable {
    public let tier: ProTier?
    public let creditsRemaining: Int
    public let monthlyQuota: Int
    public let monthlyResetAt: Date?
    public let subscriptionStatus: SubscriptionStatus
    public let subscriptionRenewsAt: Date?
    public let freeCutoutsUsed: Int?
    public let freeCutoutsRemaining: Int?
    public let freeImportsUsed: Int?
    public let freeImportsRemaining: Int?
    /// True when this device is Pro via a pre-auth checkout grant
    /// (`device_grants` row) but the caller has no Bearer token. The UI
    /// surfaces a "Sync across Macs" banner in this state.
    public let needsAccountLink: Bool?
    /// Email captured by Stripe at the pre-auth checkout. Used by the
    /// banner so the user knows which inbox to check.
    public let linkEmail: String?
}
