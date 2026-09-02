import type Stripe from "stripe";
import {
  creditsForPack,
  intervalFromPriceId,
  packFromPriceId,
  tierFromPriceId,
  type SubscriptionInterval,
} from "./stripe.js";

/**
 * Pure Stripe → client mapping for `GET /v1/billing` (Settings › Billing &
 * Invoices). Kept free of I/O so the shapes can be unit-tested without a
 * Stripe client. Snake_case keys: the app decodes with
 * `.convertFromSnakeCase` + ISO-8601 dates, same as `/v1/account`.
 */

export type BillingDiscount = {
  /** e.g. 100 for "100% off"; null when the coupon is a fixed amount. */
  percent_off: number | null;
  /** Minor units (cents) when the coupon is a fixed amount; null otherwise. */
  amount_off: number | null;
  currency: string | null;
  /** ISO-8601 end of a `repeating` coupon; null for `forever` / `once`. */
  ends_at: string | null;
};

export type BillingNextPayment = {
  /** Minor units (cents) the customer will actually be charged. */
  amount: number;
  currency: string;
  at: string;
};

export type BillingPlan = {
  name: string;
  interval: SubscriptionInterval | null;
  status: string;
  cancel_at_period_end: boolean;
  current_period_end: string | null;
  /** List price per interval in minor units, BEFORE discounts. */
  amount: number;
  currency: string;
  /** Stripe price `tax_behavior` → "incl. VAT" / "excl. VAT" caption. */
  tax_behavior: "inclusive" | "exclusive" | null;
  discount: BillingDiscount | null;
  next_payment: BillingNextPayment | null;
};

export type BillingInvoiceStatus = "paid" | "open" | "void" | "uncollectible";

export type BillingInvoice = {
  id: string;
  number: string | null;
  created: string;
  /** Invoice total in minor units (after discounts, incl. tax). */
  amount: number;
  currency: string;
  status: BillingInvoiceStatus;
  /** Human line, e.g. "Pro · Monthly" or "Top-up · 200 credits". */
  description: string;
  hosted_url: string | null;
  pdf_url: string | null;
};

export type BillingPayload = {
  plan: BillingPlan | null;
  invoices: BillingInvoice[];
};

/** Statuses that count as "the user's current plan" in the UI. */
const LIVE_SUBSCRIPTION_STATUSES = new Set(["active", "trialing", "past_due", "unpaid"]);

export function isLiveSubscriptionStatus(status: string | null | undefined): boolean {
  return !!status && LIVE_SUBSCRIPTION_STATUSES.has(status);
}

function iso(unixSeconds: number | null | undefined): string | null {
  if (typeof unixSeconds !== "number" || !Number.isFinite(unixSeconds)) return null;
  return new Date(unixSeconds * 1000).toISOString();
}

/** Only month/year are meaningful for the app; anything else → null. */
export function normalizeInterval(
  interval: string | null | undefined,
): SubscriptionInterval | null {
  if (interval === "month" || interval === "year") return interval;
  return null;
}

/**
 * Human label for an invoice or subscription line. Resolution order:
 *   1. known subscription price → "Pro · Monthly" / "Pro · Yearly"
 *   2. known top-up price → "Top-up · 200 credits"
 *   3. Stripe's own line description, else a neutral fallback.
 * Legacy tiers (starter/plus/studio) all read as "Pro" — the client only
 * knows one paid tier (`mapTierForClient` in account.ts does the same).
 */
export function describeLine(
  priceId: string | null | undefined,
  fallbackDescription: string | null | undefined,
  intervalHint: string | null | undefined = null,
): string {
  const tier = tierFromPriceId(priceId);
  if (tier) {
    const interval = intervalFromPriceId(priceId) ?? normalizeInterval(intervalHint);
    return `Pro · ${interval === "year" ? "Yearly" : "Monthly"}`;
  }
  const pack = packFromPriceId(priceId);
  if (pack) return `Top-up · ${creditsForPack(pack)} credits`;
  const desc = fallbackDescription?.trim();
  return desc && desc.length > 0 ? desc : "Aaavatar";
}

/**
 * Invoice line price id, robust to the `price` → `pricing.price_details`
 * drift between Stripe API versions (same guard as the webhook, B8).
 */
export function invoiceLinePriceId(line: unknown): string | null {
  const l = line as
    | {
        price?: { id?: string } | null;
        pricing?: { price_details?: { price?: string | null } | null } | null;
      }
    | null
    | undefined;
  return l?.price?.id ?? l?.pricing?.price_details?.price ?? null;
}

export type InvoiceLike = Pick<
  Stripe.Invoice,
  "id" | "number" | "created" | "total" | "currency" | "status" | "hosted_invoice_url" | "invoice_pdf"
> & {
  /** Structural: `Stripe.InvoiceLineItem[]` in prod, plain objects in tests. */
  lines?: { data?: unknown[] } | null;
};

/** Drafts are internal noise; everything else maps 1:1. */
export function mapInvoice(inv: InvoiceLike): BillingInvoice | null {
  const status = inv.status;
  if (status !== "paid" && status !== "open" && status !== "void" && status !== "uncollectible") {
    return null;
  }
  const line = inv.lines?.data?.[0] as { description?: string | null } | undefined;
  return {
    id: inv.id,
    number: inv.number ?? null,
    created: iso(inv.created) ?? new Date(0).toISOString(),
    amount: inv.total ?? 0,
    currency: inv.currency,
    status,
    description: describeLine(invoiceLinePriceId(line), line?.description ?? null),
    hosted_url: inv.hosted_invoice_url ?? null,
    pdf_url: inv.invoice_pdf ?? null,
  };
}

export function mapInvoices(invoices: InvoiceLike[]): BillingInvoice[] {
  return invoices
    .map(mapInvoice)
    .filter((i): i is BillingInvoice => i !== null)
    .sort((a, b) => (a.created < b.created ? 1 : a.created > b.created ? -1 : 0));
}

export type DiscountLike = Pick<Stripe.Discount, "end"> & {
  coupon: Pick<Stripe.Coupon, "percent_off" | "amount_off" | "currency">;
};

export function mapDiscount(discount: DiscountLike | null | undefined): BillingDiscount | null {
  if (!discount?.coupon) return null;
  const { percent_off, amount_off, currency } = discount.coupon;
  if (percent_off == null && amount_off == null) return null;
  return {
    percent_off: percent_off ?? null,
    amount_off: amount_off ?? null,
    currency: amount_off != null ? (currency ?? null) : null,
    ends_at: iso(discount.end),
  };
}

/** First expanded discount on the subscription (ids are skipped). */
export function firstExpandedDiscount(
  discounts: Array<string | Stripe.Discount> | null | undefined,
): Stripe.Discount | null {
  for (const d of discounts ?? []) {
    if (typeof d !== "string") return d;
  }
  return null;
}

export type SubscriptionLike = Pick<
  Stripe.Subscription,
  "status" | "cancel_at_period_end" | "current_period_end" | "discounts"
> & {
  items: {
    data: Array<{
      price: Pick<Stripe.Price, "id" | "unit_amount" | "currency" | "tax_behavior"> & {
        recurring?: { interval?: string | null } | null;
      };
    }>;
  };
};

export type UpcomingLike = {
  amount_due: number;
  currency: string;
} | null;

export function mapSubscription(sub: SubscriptionLike, upcoming: UpcomingLike): BillingPlan {
  const item = sub.items.data[0];
  const price = item?.price;
  const priceId = price?.id ?? null;
  const interval =
    intervalFromPriceId(priceId) ?? normalizeInterval(price?.recurring?.interval ?? null);
  const periodEnd = iso(sub.current_period_end);
  const taxBehavior =
    price?.tax_behavior === "inclusive" || price?.tax_behavior === "exclusive"
      ? price.tax_behavior
      : null;

  // A cancelled-at-period-end plan has no next payment: the row would lie.
  const nextPayment: BillingNextPayment | null =
    upcoming && periodEnd && !sub.cancel_at_period_end
      ? { amount: upcoming.amount_due, currency: upcoming.currency, at: periodEnd }
      : null;

  return {
    name: tierFromPriceId(priceId) ? "Pro" : describeLine(priceId, null, interval).split(" · ")[0],
    interval,
    status: sub.status,
    cancel_at_period_end: !!sub.cancel_at_period_end,
    current_period_end: periodEnd,
    amount: price?.unit_amount ?? 0,
    currency: price?.currency ?? upcoming?.currency ?? "eur",
    tax_behavior: taxBehavior,
    discount: mapDiscount(firstExpandedDiscount(sub.discounts) as DiscountLike | null),
    next_payment: nextPayment,
  };
}

/**
 * Pick the subscription to show as "the plan": the most recently renewing
 * live one. Cancelled/incomplete subs are history — the invoices list still
 * shows their charges, but the Plan card falls back to Starter client-side.
 */
export function pickCurrentSubscription<T extends SubscriptionLike>(subs: T[]): T | null {
  const live = subs.filter((s) => isLiveSubscriptionStatus(s.status));
  if (live.length === 0) return null;
  return live.sort((a, b) => (b.current_period_end ?? 0) - (a.current_period_end ?? 0))[0];
}
