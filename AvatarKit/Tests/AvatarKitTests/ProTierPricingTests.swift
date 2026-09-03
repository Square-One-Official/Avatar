// UXS-11 (UX10) — prijsweergave volgt de systeemlocale. De valuta blijft EUR
// (Stripe rekent in euro's af); alleen de notatie verschilt per locale. De oude
// hardgecodeerde "€49,90"-strings logen tegen elke niet-Nederlandse gebruiker.

import Foundation
import XCTest
@testable import AvatarKit

final class ProTierPricingTests: XCTestCase {

    func testDutchLocaleUsesCommaDecimalSeparator() {
        let price = ProTier.formatPrice(4.99, locale: Locale(identifier: "nl_NL"))
        XCTAssertTrue(price.contains("4,99"), "nl-NL hoort een komma te gebruiken, kreeg: \(price)")
    }

    func testEnglishLocaleUsesPeriodDecimalSeparator() {
        let price = ProTier.formatPrice(4.99, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(price.contains("4.99"), "en-US hoort een punt te gebruiken, kreeg: \(price)")
    }

    /// Ongeacht de locale blijft het bedrag in euro's — een Amerikaanse
    /// gebruiker mag hier geen dollarteken zien voor een EUR-afschrijving.
    func testCurrencyStaysEuroAcrossLocales() {
        for identifier in ["nl_NL", "en_US", "de_DE", "ja_JP"] {
            let price = ProTier.formatPrice(49.90, locale: Locale(identifier: identifier))
            XCTAssertTrue(
                price.contains("€") || price.uppercased().contains("EUR"),
                "\(identifier) verloor de euro-aanduiding: \(price)"
            )
            XCTAssertFalse(price.contains("$"), "\(identifier) toonde dollars: \(price)")
        }
    }

    /// De jaarprijs is 10× de maandprijs (2 maanden gratis) — die belofte staat
    /// in de paywall-copy, dus borgen we 'm hier.
    func testAnnualPriceIsTenMonths() {
        XCTAssertEqual(ProTier.pro.annualPrice, ProTier.pro.monthlyPrice * 10)
    }

    /// Billing-pagina: Stripe levert centen. `€0` (100%-korting-factuur) mag
    /// geen ",00" dragen, `€12,99` wél twee decimalen; de valuta komt van de
    /// wire en mag geen EUR-aanname zijn.
    func testMinorUnitsFormatting() {
        let nl = Locale(identifier: "nl_NL")
        let zero = ProTier.formatMinorUnits(0, currencyCode: "eur", locale: nl)
        XCTAssertTrue(zero.contains("€") && zero.contains("0") && !zero.contains(",00"), "kreeg: \(zero)")
        XCTAssertTrue(ProTier.formatMinorUnits(1299, currencyCode: "eur", locale: nl).contains("12,99"))
        let us = ProTier.formatMinorUnits(1299, currencyCode: "usd", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(us, "$12.99")
    }

    func testDisplayPricesAreNonEmpty() {
        XCTAssertFalse(ProTier.pro.monthlyPriceDisplay.isEmpty)
        XCTAssertFalse(ProTier.pro.annualPriceDisplay.isEmpty)
        XCTAssertFalse(ProTier.pro.annualPricePerMonthDisplay.isEmpty)
    }
}
