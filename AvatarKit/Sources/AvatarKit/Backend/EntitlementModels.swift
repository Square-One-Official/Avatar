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

    /// Monthly credit grant, mirrored server-side. Magic Cutout costs 1
    /// credit per image.
    public var monthlyCredits: Int { 200 }

    // Bedragen (informatief — Stripe is de bron van waarheid). De VALUTA is
    // altijd EUR omdat Stripe in euro's afrekent; alleen de NOTATIE volgt de
    // systeemlocale (UXS-11): "€4,99" in nl-NL, "€4.99" in en-US. Hardgecodeerde
    // strings logen tegen elke niet-Nederlandse gebruiker.
    /// Exact opgebouwd (cent als significand), niet via een Double-literal:
    /// `Decimal(4.99)` levert 4.99000000000000102… op en dan klopt zelfs
    /// 10× de maandprijs niet meer precies tegen de jaarprijs.
    public var monthlyPrice: Decimal { Decimal(sign: .plus, exponent: -2, significand: 499) }

    /// Jaarplan = 10× de maandprijs (2 maanden gratis, 17% korting).
    public var annualPrice: Decimal { Decimal(sign: .plus, exponent: -2, significand: 4990) }

    /// Maand-equivalent bij jaarlijkse betaling, voor "…/mo billed annually".
    public var annualPricePerMonth: Decimal { Decimal(sign: .plus, exponent: -2, significand: 416) }

    /// Display price in EUR, genoteerd volgens de systeemlocale.
    public var monthlyPriceDisplay: String { ProTier.formatPrice(monthlyPrice) }
    public var annualPriceDisplay: String { ProTier.formatPrice(annualPrice) }
    public var annualPricePerMonthDisplay: String { ProTier.formatPrice(annualPricePerMonth) }

    // De oude vaste-notatie-namen blijven bestaan omdat v1 (`Avatar/`, bevroren)
    // ze gebruikt en buiten deze story valt; ze wijzen nu naar de locale-bewuste
    // waarde, dus v1 profiteert mee zonder dat we die code aanraken.
    public var monthlyPriceEUR: String { monthlyPriceDisplay }
    public var annualPriceEUR: String { annualPriceDisplay }
    public var annualPricePerMonthEUR: String { annualPricePerMonthDisplay }

    /// EUR-bedrag in de notatie van `locale`. Los testbaar; `locale` is alleen
    /// een parameter zodat tests niet van de machine-instelling afhangen.
    public static func formatPrice(_ amount: Decimal, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = locale
        // Hele bedragen tonen we niet als "€50" maar als "€50,00" zou storen bij
        // een prijs die op ,90 eindigt — dus altijd twee decimalen, behalve als
        // het bedrag exact rond is.
        let isWhole = amount == amount.rounded(0, .plain)
        formatter.minimumFractionDigits = isWhole ? 0 : 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber)
            ?? "€\(amount)"
    }
}

private extension Decimal {
    func rounded(_ scale: Int, _ mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }
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
    /// E15.5: true voor dev-allowlisted accounts → toont de Advanced
    /// model-picker. Backend `is_dev_unlimited` (convertFromSnakeCase).
    public let isDevUnlimited: Bool?
}
