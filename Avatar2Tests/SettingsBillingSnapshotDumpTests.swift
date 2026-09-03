import AppKit
import AvatarKit
import AvatarUI
import SwiftUI
import XCTest
@testable import Avatar2

/// Visuele dump van Settings › Billing & Invoices in drie states (Pro met
/// korting, Starter, uitgelogd) — geen assert, alleen een PNG voor review.
/// Zelfde patroon als EnhanceTileSnapshotDumpTests; draait uitsluitend met:
///   TEST_RUNNER_BILLING_DUMP_DIR=<map|TMP>
@MainActor
final class SettingsBillingSnapshotDumpTests: XCTestCase {

    override func setUp() {
        super.setUp()
        EntitlementStubURLProtocol.reset()
    }

    override func tearDown() {
        EntitlementStubURLProtocol.reset()
        super.tearDown()
    }

    private let proJSON = """
        {
          "plan": {
            "name": "Pro", "interval": "month", "status": "active",
            "cancel_at_period_end": false, "current_period_end": "2026-09-07T00:00:00Z",
            "amount": 1299, "currency": "eur", "tax_behavior": "exclusive",
            "discount": { "percent_off": 100, "amount_off": null, "currency": null, "ends_at": "2027-08-07T00:00:00Z" },
            "next_payment": { "amount": 0, "currency": "eur", "at": "2026-09-07T00:00:00Z" }
          },
          "invoices": [
            { "id": "in_2", "number": "A-0002", "created": "2026-08-07T00:00:00Z", "amount": 0,
              "currency": "eur", "status": "paid", "description": "Pro · Monthly",
              "hosted_url": "https://invoice.stripe.com/i/in_2", "pdf_url": null },
            { "id": "in_1", "number": "A-0001", "created": "2026-07-07T00:00:00Z", "amount": 499,
              "currency": "eur", "status": "open", "description": "Top-up · 200 credits",
              "hosted_url": "https://invoice.stripe.com/i/in_1", "pdf_url": null }
          ]
        }
        """


    /// AuthService' `authStateChanges`-stream levert kort na init een lege
    /// initial-session en zou een eerder gezette debug-sessie overschrijven;
    /// eerst laten settelen, dán de sessie zetten.
    private func signedInAuth() async -> AuthService {
        let auth = AuthService.isolated()
        try? await Task.sleep(for: .milliseconds(250))
        auth.debugSetSession(accessToken: "test-token", email: "t@example.test")
        return auth
    }

    private func model(signedIn: Bool, pro: Bool) async -> EntitlementModel {
        let auth = signedIn ? await signedInAuth() : AuthService.isolated()
        let model = EntitlementModel(auth: auth, backendSession: EntitlementStubURLProtocol.makeSession())
        if signedIn {
            EntitlementStubURLProtocol.setStub(
                .json(200, pro ? proJSON : #"{ "plan": null, "invoices": [] }"#), forPath: "/v1/billing"
            )
            EntitlementStubURLProtocol.setStub(.json(200, """
                { "tier": \(pro ? "\"pro\"" : "null"), "credits_remaining": \(pro ? 200 : 0), "monthly_quota": \(pro ? 200 : 0),
                  "monthly_reset_at": null, "subscription_status": "\(pro ? "active" : "none")",
                  "subscription_renews_at": null, "free_cutouts_used": 0, "free_cutouts_remaining": 3,
                  "free_imports_used": 0, "free_imports_remaining": 3, "needs_account_link": false }
                """), forPath: "/v1/account")
            EntitlementStubURLProtocol.setStub(.json(200, "{}"), forPath: "/v1/feature-flags")
            await model.refresh()
            await model.refreshBilling()
        }
        return model
    }

    func testDumpBillingPage() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["BILLING_DUMP_DIR"] else { throw XCTSkip("BILLING_DUMP_DIR niet gezet") }

        let states: [(String, Bool, Bool)] = [("pro", true, true), ("starter", true, false), ("signed-out", false, false)]
        let width: CGFloat = 656
        var images: [NSImage] = []
        for (_, signedIn, pro) in states {
            let entitlement = await model(signedIn: signedIn, pro: pro)
            let page = SettingsBillingPage(entitlement: entitlement)
                .frame(width: width, alignment: .topLeading)
                .padding(.bottom, DSSpacing.gap8)
                .background(DSColor.Background.app)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: page)
            renderer.scale = 2
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            guard let img = renderer.nsImage else { continue }
            images.append(img)
        }

        let gap: CGFloat = 24
        let sheet = NSImage(size: NSSize(
            width: gap + CGFloat(images.count) * (width + gap),
            height: (images.map(\.size.height).max() ?? 0) + 2 * gap
        ))
        sheet.lockFocus()
        NSColor(white: 0.5, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: sheet.size)).fill()
        for (i, img) in images.enumerated() {
            let x = gap + CGFloat(i) * (width + gap)
            let y = sheet.size.height - gap - img.size.height
            img.draw(in: NSRect(x: x, y: y, width: img.size.width, height: img.size.height))
        }
        sheet.unlockFocus()
        let tiff = try XCTUnwrap(sheet.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let base = dir == "TMP" ? NSTemporaryDirectory() : dir
        let url = URL(fileURLWithPath: base).appendingPathComponent("settings-billing.png")
        try png.write(to: url)
        print("BILLING_DUMP: \(url.path)")
    }
}
