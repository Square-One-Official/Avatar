// Pure copy/formatting voor Settings › Billing & Invoices. Los van de view
// zodat de tekstlogica (kortingsbadge, cadans-onderschrift, status-badge)
// zonder SwiftUI-host testbaar is. Locale/tijdzone zijn parameters met de
// systeemdefault, zodat tests niet van de machine afhangen.

import AvatarKit
import Foundation

enum BillingCopy {
    /// Badge-toon; de view vertaalt dit naar DS-signaalkleuren.
    enum Tone: Equatable {
        case success, warning, error, neutral
    }

    static func price(_ minorUnits: Int, currency: String, locale: Locale = .current) -> String {
        ProTier.formatMinorUnits(minorUnits, currencyCode: currency, locale: locale)
    }

    /// "7 Aug 2026" (en-GB) / "Aug 7, 2026" (en-US) — de systeemnotatie.
    static func date(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone)
        )
    }

    /// "100% off until 7 Aug 2027" · "€5 off" · nil zonder korting.
    static func discountLabel(
        _ discount: BillingPayload.Discount?,
        fallbackCurrency: String,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String? {
        guard let discount else { return nil }
        let amount: String
        if let percent = discount.percentOff {
            let number = percent.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
            amount = "\(number)% off"
        } else if let off = discount.amountOff {
            amount = "\(price(off, currency: discount.currency ?? fallbackCurrency, locale: locale)) off"
        } else {
            return nil
        }
        guard let end = discount.endsAt else { return amount }
        return "\(amount) until \(date(end, locale: locale, timeZone: timeZone))"
    }

    /// Onder de plannaam: wat er met het abonnement gaat gebeuren.
    static func renewalCaption(
        _ plan: BillingPayload.Plan,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        if plan.cancelAtPeriodEnd {
            if let end = plan.currentPeriodEnd {
                return "Cancels on \(date(end, locale: locale, timeZone: timeZone))"
            }
            return "Cancels at the end of this period"
        }
        switch plan.status {
        case "past_due", "unpaid": return "Payment overdue"
        case "trialing": return "Trial · renews automatically"
        default: return "Renews automatically"
        }
    }

    /// Onder de prijs: "Per month, excl. VAT".
    static func cadenceCaption(_ plan: BillingPayload.Plan) -> String {
        let cadence: String
        switch plan.interval {
        case .month: cadence = "Per month"
        case .year: cadence = "Per year"
        case nil: cadence = "Per billing period"
        }
        switch plan.taxBehavior {
        case .exclusive: return "\(cadence), excl. VAT"
        case .inclusive: return "\(cadence), incl. VAT"
        case nil: return cadence
        }
    }

    /// Onder het saldo. 14.7 (audit B8): alleen een toekomstige refill-datum
    /// tonen — een stale `current_period_end` valt terug op periodloze copy.
    /// UXS-11: een Starter kán credits hebben (top-up/restant), dus de copy
    /// mag het getal ernaast niet tegenspreken.
    static func creditsSubtitle(
        upcomingReset: Date?,
        isPro: Bool,
        credits: Int,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        if let upcomingReset {
            return "Refills on \(date(upcomingReset, locale: locale, timeZone: timeZone))"
        }
        if isPro { return "Refills monthly with your plan" }
        return credits > 0
            ? "Top-up credits — you can use these on any plan"
            : "Credits come with a Pro plan"
    }

    /// Pack-prijs in dezelfde locale-notatie als de rest van de pagina (de
    /// `priceEUR`-string op CreditPack is een vaste nl-notatie voor v1).
    static func packPrice(_ pack: CreditPack, locale: Locale = .current) -> String {
        let cents = Int((pack.centsPerCredit * Double(pack.credits)).rounded())
        return price(cents, currency: "eur", locale: locale)
    }

    /// "Save 37%" t.o.v. het kleinste pack (dezelfde ankerlogica als de
    /// paywall-ladder). nil voor het basispack — geen badge. Bewust géén
    /// per-credit-bedragen: de gebruiker kiest een hoeveelheid, niet een tarief.
    static func savingsPercent(_ pack: CreditPack) -> Int? {
        let base = CreditPack.displayOrder.first ?? .credits50
        guard pack != base, base.centsPerCredit > 0 else { return nil }
        let pct = Int(((1 - pack.centsPerCredit / base.centsPerCredit) * 100).rounded())
        return pct > 0 ? pct : nil
    }

    static func savingsLabel(_ pack: CreditPack) -> String? {
        savingsPercent(pack).map { "Save \($0)%" }
    }

    static func invoiceStatus(_ status: BillingPayload.InvoiceStatus) -> (label: String, tone: Tone) {
        switch status {
        case .paid: return ("Paid", .success)
        case .open: return ("Due", .warning)
        case .uncollectible: return ("Failed", .error)
        case .void: return ("Void", .neutral)
        }
    }

    /// "Pro · Monthly" op de factuurrij komt van de server; dit is de
    /// datumkolom ernaast.
    static func invoiceDate(_ invoice: BillingPayload.Invoice, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        date(invoice.created, locale: locale, timeZone: timeZone)
    }
}
