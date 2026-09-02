// Settings › Billing & Invoices — pure copy (BillingCopy) + de
// EntitlementModel-laadpaden via de E47.1-stub-sessie. Locale/tijdzone zijn
// vastgepind (en_GB, UTC) zodat de datumnotatie niet van de machine afhangt.

import AvatarKit
import Foundation
import XCTest
@testable import Avatar2

@MainActor
final class SettingsBillingTests: XCTestCase {

    private let locale = Locale(identifier: "en_GB")
    private let utc = TimeZone(identifier: "UTC")!

    override func setUp() {
        super.setUp()
        EntitlementStubURLProtocol.reset()
    }

    override func tearDown() {
        EntitlementStubURLProtocol.reset()
        super.tearDown()
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func plan(
        interval: SubscriptionInterval? = .month,
        status: String = "active",
        cancelAtPeriodEnd: Bool = false,
        taxBehavior: BillingPayload.TaxBehavior? = .exclusive,
        discount: BillingPayload.Discount? = nil
    ) -> BillingPayload.Plan {
        BillingPayload.Plan(
            name: "Pro",
            interval: interval,
            status: status,
            cancelAtPeriodEnd: cancelAtPeriodEnd,
            currentPeriodEnd: date("2026-09-07T00:00:00Z"),
            amount: 1299,
            currency: "eur",
            taxBehavior: taxBehavior,
            discount: discount,
            nextPayment: nil
        )
    }

    // MARK: - BillingCopy

    func testDiscountLabelPercentWithEndDate() {
        let discount = BillingPayload.Discount(
            percentOff: 100, amountOff: nil, currency: nil, endsAt: date("2027-08-07T00:00:00Z")
        )
        XCTAssertEqual(
            BillingCopy.discountLabel(discount, fallbackCurrency: "eur", locale: locale, timeZone: utc),
            "100% off until 7 Aug 2027"
        )
    }

    func testDiscountLabelAmountOffWithoutEnd() {
        let discount = BillingPayload.Discount(percentOff: nil, amountOff: 500, currency: "eur", endsAt: nil)
        let label = BillingCopy.discountLabel(discount, fallbackCurrency: "usd", locale: locale, timeZone: utc)
        XCTAssertEqual(label, "€5 off")
        XCTAssertNil(BillingCopy.discountLabel(nil, fallbackCurrency: "eur", locale: locale, timeZone: utc))
    }

    func testCadenceCaptionCombinesIntervalAndTax() {
        XCTAssertEqual(BillingCopy.cadenceCaption(plan()), "Per month, excl. VAT")
        XCTAssertEqual(BillingCopy.cadenceCaption(plan(interval: .year, taxBehavior: .inclusive)), "Per year, incl. VAT")
        XCTAssertEqual(BillingCopy.cadenceCaption(plan(interval: nil, taxBehavior: nil)), "Per billing period")
    }

    func testRenewalCaptionFollowsSubscriptionState() {
        XCTAssertEqual(BillingCopy.renewalCaption(plan(), locale: locale, timeZone: utc), "Renews automatically")
        XCTAssertEqual(
            BillingCopy.renewalCaption(plan(cancelAtPeriodEnd: true), locale: locale, timeZone: utc),
            "Cancels on 7 Sep 2026"
        )
        XCTAssertEqual(BillingCopy.renewalCaption(plan(status: "past_due"), locale: locale, timeZone: utc), "Payment overdue")
    }

    func testCreditsSubtitleMovedFromAccount() {
        let reset = date("2026-10-01T00:00:00Z")
        XCTAssertEqual(
            BillingCopy.creditsSubtitle(upcomingReset: reset, isPro: true, credits: 12, locale: locale, timeZone: utc),
            "Refills on 1 Oct 2026"
        )
        XCTAssertEqual(
            BillingCopy.creditsSubtitle(upcomingReset: nil, isPro: true, credits: 0, locale: locale, timeZone: utc),
            "Refills monthly with your plan"
        )
        XCTAssertEqual(
            BillingCopy.creditsSubtitle(upcomingReset: nil, isPro: false, credits: 34, locale: locale, timeZone: utc),
            "Top-up credits — you can use these on any plan"
        )
        XCTAssertEqual(
            BillingCopy.creditsSubtitle(upcomingReset: nil, isPro: false, credits: 0, locale: locale, timeZone: utc),
            "Credits come with a Pro plan"
        )
    }

    func testPackPriceMatchesLadder() {
        XCTAssertEqual(BillingCopy.packPrice(.credits50, locale: locale), "€1.99")
        XCTAssertEqual(BillingCopy.packPrice(.credits200, locale: locale), "€4.99")
        XCTAssertEqual(BillingCopy.packPrice(.credits750, locale: locale), "€14.99")
    }

    /// Save-badge t.o.v. het kleinste pack; het basispack krijgt er geen.
    func testSavingsBadgeRelativeToSmallestPack() {
        XCTAssertNil(BillingCopy.savingsLabel(.credits50))
        XCTAssertEqual(BillingCopy.savingsLabel(.credits200), "Save 37%")
        XCTAssertEqual(BillingCopy.savingsLabel(.credits750), "Save 50%")
    }

    func testInvoiceStatusBadges() {
        XCTAssertEqual(BillingCopy.invoiceStatus(.paid).label, "Paid")
        XCTAssertEqual(BillingCopy.invoiceStatus(.paid).tone, .success)
        XCTAssertEqual(BillingCopy.invoiceStatus(.open).tone, .warning)
        XCTAssertEqual(BillingCopy.invoiceStatus(.uncollectible).tone, .error)
        XCTAssertEqual(BillingCopy.invoiceStatus(.void).tone, .neutral)
    }

    func testPriceFormatsMinorUnitsInWireCurrency() {
        XCTAssertEqual(BillingCopy.price(0, currency: "eur", locale: locale), "€0")
        XCTAssertEqual(BillingCopy.price(1299, currency: "eur", locale: locale), "€12.99")
    }

    // MARK: - Invoice URL choice

    func testInvoiceURLPrefersPDFAndRejectsNonWebSchemes() {
        func invoice(pdf: String?, hosted: String?) -> BillingPayload.Invoice {
            BillingPayload.Invoice(
                id: "in_1", number: nil, created: .now, amount: 0, currency: "eur",
                status: .paid, description: "Pro · Monthly", hostedUrl: hosted, pdfUrl: pdf
            )
        }
        XCTAssertEqual(
            EntitlementModel.invoiceURL(for: invoice(pdf: "https://pay.stripe.com/x.pdf", hosted: "https://invoice.stripe.com/x"))?.absoluteString,
            "https://pay.stripe.com/x.pdf"
        )
        XCTAssertEqual(
            EntitlementModel.invoiceURL(for: invoice(pdf: nil, hosted: "https://invoice.stripe.com/x"))?.absoluteString,
            "https://invoice.stripe.com/x"
        )
        XCTAssertNil(EntitlementModel.invoiceURL(for: invoice(pdf: "file:///etc/passwd", hosted: nil)))
        XCTAssertNil(EntitlementModel.invoiceURL(for: invoice(pdf: nil, hosted: nil)))
    }

    // MARK: - EntitlementModel.refreshBilling


    /// AuthService' `authStateChanges`-stream levert kort na init een lege
    /// initial-session en zou een eerder gezette debug-sessie overschrijven;
    /// eerst laten settelen, dán de sessie zetten.
    private func signedInAuth() async -> AuthService {
        let auth = AuthService()
        try? await Task.sleep(for: .milliseconds(250))
        auth.debugSetSession(accessToken: "test-token", email: "t@example.test")
        return auth
    }

    private func makeModel(signedIn: Bool) async -> EntitlementModel {
        let auth = signedIn ? await signedInAuth() : AuthService()
        return EntitlementModel(auth: auth, backendSession: EntitlementStubURLProtocol.makeSession())
    }

    private let billingJSON = """
        {
          "plan": {
            "name": "Pro", "interval": "month", "status": "active",
            "cancel_at_period_end": false, "current_period_end": "2026-09-07T00:00:00Z",
            "amount": 1299, "currency": "eur", "tax_behavior": "exclusive",
            "discount": { "percent_off": 100, "amount_off": null, "currency": null, "ends_at": "2027-08-07T00:00:00Z" },
            "next_payment": { "amount": 0, "currency": "eur", "at": "2026-09-07T00:00:00Z" }
          },
          "invoices": [
            { "id": "in_1", "number": "A-0001", "created": "2026-08-07T00:00:00Z", "amount": 0,
              "currency": "eur", "status": "paid", "description": "Pro · Monthly",
              "hosted_url": "https://invoice.stripe.com/i/in_1", "pdf_url": null }
          ]
        }
        """

    func testRefreshBillingSignedOutStaysEmptyWithoutRequest() async {
        // Geen stub op /v1/billing: een request zou als fout landen.
        let model = await makeModel(signedIn: false)
        await model.refreshBilling()
        XCTAssertNil(model.billing)
        XCTAssertNil(model.billingError)
    }

    func testRefreshBillingLoadsPlanAndInvoices() async {
        EntitlementStubURLProtocol.setStub(.json(200, billingJSON), forPath: "/v1/billing")
        let model = await makeModel(signedIn: true)

        await model.refreshBilling()

        XCTAssertEqual(model.billing?.plan?.name, "Pro")
        XCTAssertEqual(model.billing?.plan?.nextPayment?.amount, 0)
        XCTAssertEqual(model.billing?.invoices.first?.description, "Pro · Monthly")
        XCTAssertNil(model.billingError)
        XCTAssertFalse(model.isLoadingBilling)
    }

    func testRefreshBillingServerErrorKeepsPreviousPayload() async {
        EntitlementStubURLProtocol.setStub(.json(200, billingJSON), forPath: "/v1/billing")
        let model = await makeModel(signedIn: true)
        await model.refreshBilling()
        XCTAssertNotNil(model.billing)

        EntitlementStubURLProtocol.setStub(.json(500, #"{"error":"billing_failed"}"#), forPath: "/v1/billing")
        await model.refreshBilling()

        XCTAssertNotNil(model.billing, "vorige payload blijft staan — geen flits naar leeg")
        XCTAssertNotNil(model.billingError)
    }

    func testSignOutClearsBilling() async {
        EntitlementStubURLProtocol.setStub(.json(200, billingJSON), forPath: "/v1/billing")
        let model = await makeModel(signedIn: true)
        await model.refreshBilling()
        XCTAssertNotNil(model.billing)

        model.signOutAccount()

        XCTAssertNil(model.billing)
        XCTAssertNil(model.billingError)
    }
}
