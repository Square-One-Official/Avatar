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

    func testDisplayPricesAreNonEmpty() {
        XCTAssertFalse(ProTier.pro.monthlyPriceDisplay.isEmpty)
        XCTAssertFalse(ProTier.pro.annualPriceDisplay.isEmpty)
        XCTAssertFalse(ProTier.pro.annualPricePerMonthDisplay.isEmpty)
    }
}
