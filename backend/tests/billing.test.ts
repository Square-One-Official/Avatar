// Pure-mapping tests for GET /v1/billing (lib/billing.ts). Price ids come
// from env at module load, so they're pinned BEFORE the dynamic import; the
// Stripe client (lib/stripe.ts) also constructs at import and needs *a* key —
// nothing here ever talks to Stripe.
process.env.STRIPE_SECRET_KEY ??= "sk_test_billing_unit_tests";
process.env.PRICE_ID_PRO = "price_pro_month";
process.env.PRICE_ID_PRO_ANNUAL = "price_pro_year";
process.env.PRICE_ID_TOPUP_200 = "price_topup_200";

import assert from "node:assert/strict";
import test from "node:test";

const billing = await import("../lib/billing.js");

const AUG_7_2026 = Date.UTC(2026, 7, 7) / 1000;
const SEP_7_2026 = Date.UTC(2026, 8, 7) / 1000;
const AUG_7_2027 = Date.UTC(2027, 7, 7) / 1000;

test("describeLine: subscription prices → Pro · cadence", () => {
  assert.equal(billing.describeLine("price_pro_month", null), "Pro · Monthly");
  assert.equal(billing.describeLine("price_pro_year", null), "Pro · Yearly");
});

test("describeLine: top-up price → Top-up · credits", () => {
  assert.equal(billing.describeLine("price_topup_200", null), "Top-up · 200 credits");
});

test("describeLine: unknown price falls back to Stripe's description, then a neutral label", () => {
  assert.equal(billing.describeLine("price_unknown", "  Custom line "), "Custom line");
  assert.equal(billing.describeLine(null, ""), "Aaavatar");
});

test("mapInvoice: paid invoice maps 1:1, newest first, drafts dropped", () => {
  const paid = {
    id: "in_1",
    number: "A-0001",
    created: AUG_7_2026,
    total: 0,
    currency: "eur",
    status: "paid" as const,
    hosted_invoice_url: "https://invoice.stripe.com/i/in_1",
    invoice_pdf: "https://pay.stripe.com/invoice/in_1/pdf",
    lines: { data: [{ price: { id: "price_pro_month" }, description: "ignored" }] },
  };
  const older = { ...paid, id: "in_0", created: AUG_7_2026 - 86_400, status: "open" as const };
  const draft = { ...paid, id: "in_draft", status: "draft" as const };

  const mapped = billing.mapInvoices([older, draft, paid]);
  assert.deepEqual(
    mapped.map((i) => i.id),
    ["in_1", "in_0"],
  );
  assert.deepEqual(mapped[0], {
    id: "in_1",
    number: "A-0001",
    created: "2026-08-07T00:00:00.000Z",
    amount: 0,
    currency: "eur",
    status: "paid",
    description: "Pro · Monthly",
    hosted_url: "https://invoice.stripe.com/i/in_1",
    pdf_url: "https://pay.stripe.com/invoice/in_1/pdf",
  });
});

test("invoiceLinePriceId: survives the price → pricing.price_details drift", () => {
  assert.equal(billing.invoiceLinePriceId({ price: { id: "price_a" } }), "price_a");
  assert.equal(
    billing.invoiceLinePriceId({ pricing: { price_details: { price: "price_b" } } }),
    "price_b",
  );
  assert.equal(billing.invoiceLinePriceId(undefined), null);
});

function proSubscription(overrides: Record<string, unknown> = {}) {
  return {
    id: "sub_1",
    status: "active",
    cancel_at_period_end: false,
    current_period_end: SEP_7_2026,
    discounts: [
      {
        end: AUG_7_2027,
        coupon: { percent_off: 100, amount_off: null, currency: null },
      },
    ],
    items: {
      data: [
        {
          price: {
            id: "price_pro_month",
            unit_amount: 1299,
            currency: "eur",
            tax_behavior: "exclusive",
            recurring: { interval: "month" },
          },
        },
      ],
    },
    ...overrides,
  } as unknown as Parameters<typeof billing.mapSubscription>[0];
}

test("mapSubscription: list price, 100%-off coupon with end date, next payment from the preview", () => {
  const plan = billing.mapSubscription(proSubscription(), { amount_due: 0, currency: "eur" });
  assert.deepEqual(plan, {
    name: "Pro",
    interval: "month",
    status: "active",
    cancel_at_period_end: false,
    current_period_end: "2026-09-07T00:00:00.000Z",
    amount: 1299,
    currency: "eur",
    tax_behavior: "exclusive",
    discount: { percent_off: 100, amount_off: null, currency: null, ends_at: "2027-08-07T00:00:00.000Z" },
    next_payment: { amount: 0, currency: "eur", at: "2026-09-07T00:00:00.000Z" },
  });
});

test("mapSubscription: cancel_at_period_end drops the next payment; no discount → null", () => {
  const plan = billing.mapSubscription(
    proSubscription({ cancel_at_period_end: true, discounts: ["di_unexpanded"] }),
    { amount_due: 1299, currency: "eur" },
  );
  assert.equal(plan.cancel_at_period_end, true);
  assert.equal(plan.next_payment, null);
  assert.equal(plan.discount, null);
});

test("mapSubscription: yearly price id wins over the recurring hint", () => {
  const plan = billing.mapSubscription(
    proSubscription({
      items: {
        data: [
          {
            price: {
              id: "price_pro_year",
              unit_amount: 4990,
              currency: "eur",
              tax_behavior: "unspecified",
              recurring: { interval: "month" },
            },
          },
        ],
      },
    }),
    null,
  );
  assert.equal(plan.interval, "year");
  assert.equal(plan.tax_behavior, null);
  assert.equal(plan.next_payment, null);
});

test("pickCurrentSubscription: live status only, latest period end wins", () => {
  const canceled = proSubscription({ id: "sub_old", status: "canceled", current_period_end: AUG_7_2027 });
  const pastDue = proSubscription({ id: "sub_pd", status: "past_due", current_period_end: AUG_7_2026 });
  const active = proSubscription({ id: "sub_now", status: "active", current_period_end: SEP_7_2026 });
  const picked = billing.pickCurrentSubscription([canceled, pastDue, active]);
  assert.equal((picked as { id: string }).id, "sub_now");
  assert.equal(billing.pickCurrentSubscription([canceled]), null);
});
