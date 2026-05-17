import Stripe from "stripe";

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: "2025-02-24.acacia",
});

/**
 * Subscription tiers.
 *
 * `pro` is the live single-tier offering driven by the v1 client (€4,99 /
 * mo or €49,90 / yr — both grant 200 credits per month). `starter`,
 * `plus`, `studio` are legacy tiers kept around for backward-compat with
 * old subscription rows; the v1 client never asks for them.
 */
export type Tier = "starter" | "plus" | "studio" | "pro";

/** Billing interval for Pro. Yearly is 17% cheaper (2 months free). */
export type SubscriptionInterval = "month" | "year";

const PRICE_IDS: Record<Tier, string | undefined> = {
  starter: process.env.PRICE_ID_STARTER,
  plus: process.env.PRICE_ID_PLUS,
  studio: process.env.PRICE_ID_STUDIO,
  pro: process.env.PRICE_ID_PRO,
};

/** Pro yearly price IDs. Only `pro` has a yearly variant today. */
const ANNUAL_PRICE_IDS: Partial<Record<Tier, string | undefined>> = {
  pro: process.env.PRICE_ID_PRO_ANNUAL,
};

const CREDITS_PER_TIER: Record<Tier, number> = {
  starter: 20,
  plus: 50,
  studio: 150,
  pro: 200,
};

export function priceIdForTier(
  tier: Tier,
  interval: SubscriptionInterval = "month",
): string | undefined {
  if (interval === "year") {
    return ANNUAL_PRICE_IDS[tier] ?? undefined;
  }
  return PRICE_IDS[tier];
}

export function creditsForTier(tier: Tier): number {
  return CREDITS_PER_TIER[tier];
}

export function tierFromPriceId(priceId: string | undefined | null): Tier | null {
  if (!priceId) return null;
  for (const t of Object.keys(PRICE_IDS) as Tier[]) {
    if (PRICE_IDS[t] === priceId) return t;
    if (ANNUAL_PRICE_IDS[t] === priceId) return t;
  }
  return null;
}

/** Resolve whether a Stripe price ID corresponds to a yearly billing cadence. */
export function intervalFromPriceId(
  priceId: string | undefined | null,
): SubscriptionInterval | null {
  if (!priceId) return null;
  for (const t of Object.keys(ANNUAL_PRICE_IDS) as Tier[]) {
    if (ANNUAL_PRICE_IDS[t] === priceId) return "year";
  }
  for (const t of Object.keys(PRICE_IDS) as Tier[]) {
    if (PRICE_IDS[t] === priceId) return "month";
  }
  return null;
}

/**
 * One-time credit packs sold via /v1/checkout/topup.
 * The pack key is what the client sends in the request body.
 *
 * Pricing ladder (decoy effect — bigger pack = better value):
 *   credits50  €1,99  → €0,040 / credit
 *   credits200 €4,99  → €0,025 / credit
 *   credits750 €14,99 → €0,020 / credit  (≈ "20% extra" vs Standaard)
 */
export type CreditPack = "credits50" | "credits200" | "credits750";

const TOPUP_PRICE_IDS: Record<CreditPack, string | undefined> = {
  credits50: process.env.PRICE_ID_TOPUP_50,
  credits200: process.env.PRICE_ID_TOPUP_200,
  credits750: process.env.PRICE_ID_TOPUP_750,
};

const TOPUP_CREDITS: Record<CreditPack, number> = {
  credits50: 50,
  credits200: 200,
  credits750: 750,
};

export function priceIdForPack(pack: CreditPack): string | undefined {
  return TOPUP_PRICE_IDS[pack];
}

export function creditsForPack(pack: CreditPack): number {
  return TOPUP_CREDITS[pack];
}

/** Reverse-lookup. Used by the webhook to recognise topup invoices. */
export function packFromPriceId(priceId: string | undefined | null): CreditPack | null {
  if (!priceId) return null;
  for (const p of Object.keys(TOPUP_PRICE_IDS) as CreditPack[]) {
    if (TOPUP_PRICE_IDS[p] === priceId) return p;
  }
  return null;
}

/** Type-guard: is the value a known pack ID? Used to validate request bodies. */
export function isCreditPack(value: unknown): value is CreditPack {
  return value === "credits50" || value === "credits200" || value === "credits750";
}

/** Type-guard for subscription interval (request validation). */
export function isSubscriptionInterval(value: unknown): value is SubscriptionInterval {
  return value === "month" || value === "year";
}

/**
 * Live-validated lookup of an incoming Stripe price ID (audit HIGH #6).
 *
 * The synchronous helpers above (`tierFromPriceId`, `packFromPriceId`,
 * `intervalFromPriceId`) trust the local env-var map. That's fine for
 * building outbound checkout sessions where we already know our own IDs,
 * but the webhook handler and the yearly-credits cron both *receive* a
 * price ID from outside and dispatch credit grants based on it. If env
 * has drifted — stale test price, dropped product, copy-paste mix-up
 * between live and test mode — the env-only path either grants credits
 * for a price we didn't intend or silently no-ops on one we did. Both
 * leak revenue or trust.
 *
 * `resolvePriceLive` adds two guards on top of the env lookup:
 *   1. The price must be known to our env (so an attacker who could
 *      inject an arbitrary price ID can't trick us into grantng credits
 *      for an unrelated product).
 *   2. The price must exist in Stripe AND be `active`. Catches local
 *      env drift, stale price IDs, and the live/test-mode mix-up.
 *
 * Results are cached in-memory keyed by price ID. Fluid Compute reuses
 * function instances across invocations, so warm functions amortise the
 * `prices.retrieve` cost over many webhook deliveries.
 */
export interface ResolvedPrice {
  tier: Tier | null;
  pack: CreditPack | null;
  interval: SubscriptionInterval | null;
  active: boolean;
  productId: string;
}

const priceCache = new Map<string, ResolvedPrice | null>();

export async function resolvePriceLive(
  priceId: string | undefined | null,
): Promise<ResolvedPrice | null> {
  if (!priceId) return null;

  // Negative caching included: an unknown price stays unknown for the
  // lifetime of this function instance so we don't beat on Stripe with a
  // bad ID on every webhook retry.
  if (priceCache.has(priceId)) {
    return priceCache.get(priceId) ?? null;
  }

  // Local map gate first — keeps us from leaking signal about which
  // price IDs are interesting to attackers via Stripe rate-limit
  // patterns. (`stripe.prices.retrieve` is cheap, but no reason to
  // call it for IDs we don't recognise.)
  const tier = tierFromPriceId(priceId);
  const pack = packFromPriceId(priceId);
  if (!tier && !pack) {
    console.warn("resolvePriceLive: price not in local map", priceId);
    priceCache.set(priceId, null);
    return null;
  }

  try {
    const price = await stripe.prices.retrieve(priceId);
    if (!price.active) {
      console.warn("resolvePriceLive: price exists but is inactive", priceId);
      priceCache.set(priceId, null);
      return null;
    }
    const productId = typeof price.product === "string" ? price.product : price.product.id;
    const resolved: ResolvedPrice = {
      tier,
      pack,
      interval: intervalFromPriceId(priceId),
      active: price.active,
      productId,
    };
    priceCache.set(priceId, resolved);
    return resolved;
  } catch (err) {
    // Stripe round-trip failed — do NOT cache so a transient outage
    // doesn't poison the lookup. Caller treats null as "skip / no-op",
    // which preserves idempotency: the webhook will be redelivered.
    console.error("resolvePriceLive: stripe.prices.retrieve failed", { priceId, err });
    return null;
  }
}
