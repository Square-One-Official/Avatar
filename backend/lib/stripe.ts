import Stripe from "stripe";

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: "2025-02-24.acacia",
});

/**
 * Subscription tiers.
 *
 * `pro` is the live single-tier offering driven by the v1 client (€4,99 /
 * 200 credits). `starter`, `plus`, `studio` are legacy tiers kept around
 * for backward-compat with old subscription rows; the v1 client never asks
 * for them.
 */
export type Tier = "starter" | "plus" | "studio" | "pro";

const PRICE_IDS: Record<Tier, string | undefined> = {
  starter: process.env.PRICE_ID_STARTER,
  plus: process.env.PRICE_ID_PLUS,
  studio: process.env.PRICE_ID_STUDIO,
  pro: process.env.PRICE_ID_PRO,
};

const CREDITS_PER_TIER: Record<Tier, number> = {
  starter: 20,
  plus: 50,
  studio: 150,
  pro: 200,
};

export function priceIdForTier(tier: Tier): string | undefined {
  return PRICE_IDS[tier];
}

export function creditsForTier(tier: Tier): number {
  return CREDITS_PER_TIER[tier];
}

export function tierFromPriceId(priceId: string | undefined | null): Tier | null {
  if (!priceId) return null;
  for (const t of Object.keys(PRICE_IDS) as Tier[]) {
    if (PRICE_IDS[t] === priceId) return t;
  }
  return null;
}

/**
 * One-time credit packs sold via /v1/checkout/topup.
 * The pack key is what the client sends in the request body.
 */
export type CreditPack = "credits200";

const TOPUP_PRICE_IDS: Record<CreditPack, string | undefined> = {
  credits200: process.env.PRICE_ID_TOPUP_200,
};

const TOPUP_CREDITS: Record<CreditPack, number> = {
  credits200: 200,
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
