import type { VercelRequest, VercelResponse } from "@vercel/node";
import type Stripe from "stripe";
import {
  stripe,
  creditsForTier,
  creditsForPack,
  intervalFromPriceId,
  tierFromPriceId,
  packFromPriceId,
  type Tier,
} from "../lib/stripe.js";
import { findOrCreateUserByEmail, supabase } from "../lib/supabase.js";

// Stripe webhook signature verification requires the raw request body.
export const config = {
  api: {
    bodyParser: false,
  },
};

async function readRaw(req: VercelRequest): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : chunk);
  }
  return Buffer.concat(chunks);
}

async function findUserByCustomerId(customerId: string): Promise<string | null> {
  const { data } = await supabase
    .from("users")
    .select("id")
    .eq("stripe_customer_id", customerId)
    .maybeSingle();
  return (data?.id as string | undefined) ?? null;
}

/**
 * Resolve the Supabase user that owns `customerId`, even if no link exists
 * in `public.users` yet. Used by subscription / invoice handlers because in
 * the pre-auth checkout flow Stripe can deliver `customer.subscription.*`
 * and `invoice.paid` BEFORE `checkout.session.completed` — so the
 * `users.stripe_customer_id` link from the session handler may not be in
 * place yet.
 *
 * Lookup order:
 *   1. `users.stripe_customer_id` match (fast path, the link exists).
 *   2. Stripe customer's email → `findOrCreateUserByEmail` (the link will
 *      be written by the session handler when it arrives, but we already
 *      have what we need).
 *
 * Returns null only if the customer has no email at all (shouldn't happen
 * for our flows — Stripe Checkout always collects one).
 */
async function resolveUserForCustomer(customerId: string): Promise<string | null> {
  const direct = await findUserByCustomerId(customerId);
  if (direct) return direct;

  try {
    const customer = await stripe.customers.retrieve(customerId);
    if (customer.deleted) return null;
    const email = customer.email;
    if (!email) return null;
    const userId = await findOrCreateUserByEmail(email);
    // Stamp the link so subsequent events take the fast path.
    await supabase
      .from("users")
      .upsert({ id: userId, stripe_customer_id: customerId }, { onConflict: "id" });
    return userId;
  } catch (err) {
    console.error("resolveUserForCustomer failed", { customerId, err });
    return null;
  }
}

async function upsertSubscription(sub: Stripe.Subscription, userId: string) {
  const priceId = sub.items.data[0]?.price.id;
  const tier: Tier | null = tierFromPriceId(priceId);
  if (!tier) {
    console.warn("Unknown price ID on subscription", priceId);
    return;
  }
  await supabase.from("subscriptions").upsert(
    {
      id: sub.id,
      user_id: userId,
      tier,
      status: sub.status,
      monthly_credits: creditsForTier(tier),
      current_period_start: new Date(sub.current_period_start * 1000).toISOString(),
      current_period_end: new Date(sub.current_period_end * 1000).toISOString(),
      cancel_at_period_end: sub.cancel_at_period_end,
    },
    { onConflict: "id" },
  );
}

async function grantPeriodCredits(opts: {
  userId: string;
  tier: Tier;
  invoiceId: string;
}) {
  // Idempotent: the ref column has a unique index in SQL, so a retry on the
  // same invoice will violate and be ignored.
  const { error } = await supabase.from("credit_ledger").insert({
    user_id: opts.userId,
    delta: creditsForTier(opts.tier),
    reason: "period_renewal",
    ref: opts.invoiceId,
  });
  if (error && !/duplicate key/i.test(error.message)) {
    throw error;
  }
}

/**
 * Grants a one-time topup pack's credits. Idempotency uses the same
 * (reason, ref) unique-index pattern as period renewals — see
 * `sql/002_v1_extensions.sql` for the index on reason='topup_pack'.
 */
async function grantTopupCredits(opts: {
  userId: string;
  credits: number;
  invoiceId: string;
}) {
  const { error } = await supabase.from("credit_ledger").insert({
    user_id: opts.userId,
    delta: opts.credits,
    reason: "topup_pack",
    ref: opts.invoiceId,
  });
  if (error && !/duplicate key/i.test(error.message)) {
    throw error;
  }
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const sig = req.headers["stripe-signature"];
  if (!sig || typeof sig !== "string") {
    res.status(400).json({ error: "Missing signature" });
    return;
  }

  const raw = await readRaw(req);
  const secret = process.env.STRIPE_WEBHOOK_SECRET!;

  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(raw, sig, secret);
  } catch (err) {
    console.error("Invalid Stripe signature", err);
    res.status(400).json({ error: "Invalid signature" });
    return;
  }

  try {
    switch (event.type) {
      case "checkout.session.completed": {
        const session = event.data.object as Stripe.Checkout.Session;
        const customerId = typeof session.customer === "string" ? session.customer : session.customer?.id;

        // Resolve which Supabase user owns this checkout. Two paths:
        //   1. Authed flow ("subscribe.ts" / "topup.ts"): metadata carries
        //      supabase_user_id from session creation.
        //   2. Anonymous flow ("subscribe-anonymous.ts"): no
        //      supabase_user_id; we have customer_details.email collected by
        //      Stripe and a device_fingerprint in metadata. Look up / create
        //      the auth user by email and remember the device→user grant so
        //      the macOS app can recognise this Mac as Pro on subsequent
        //      /v1/account requests without forcing sign-in.
        let userId = session.metadata?.supabase_user_id as string | undefined;
        const deviceFingerprint = session.metadata?.device_fingerprint as string | undefined;
        if (!userId && session.metadata?.flow === "subscribe_anonymous") {
          const email = session.customer_details?.email;
          if (!email) {
            console.error("subscribe_anonymous session has no customer_details.email", { sessionId: session.id });
            break;
          }
          userId = await findOrCreateUserByEmail(email);
        }

        if (userId && customerId) {
          await supabase
            .from("users")
            .upsert({ id: userId, stripe_customer_id: customerId }, { onConflict: "id" });
        }
        if (userId && deviceFingerprint) {
          // Idempotent: upsert on the fingerprint PK lets a re-delivered
          // event re-stamp the same row without erroring.
          const { error: grantErr } = await supabase
            .from("device_grants")
            .upsert(
              {
                device_fingerprint: deviceFingerprint,
                user_id: userId,
                source: "stripe_checkout",
              },
              { onConflict: "device_fingerprint" },
            );
          if (grantErr) console.error("device_grants upsert failed", grantErr);
        }

        // One-time top-up packs (mode: "payment", flow: "topup") grant credits
        // here. Subscription renewals are handled by `invoice.paid` instead.
        if (session.mode === "payment" && session.metadata?.flow === "topup" && userId) {
          const pack = session.metadata?.pack as string | undefined;
          // Look up the line item to validate the price ID instead of trusting
          // the metadata blindly. (Stripe metadata is client-controlled at
          // create time but we set it ourselves, so this is mostly defence.)
          const lines = await stripe.checkout.sessions.listLineItems(session.id, { limit: 1 });
          const priceId = lines.data[0]?.price?.id;
          const validatedPack = packFromPriceId(priceId);
          if (validatedPack && validatedPack === pack) {
            await grantTopupCredits({
              userId,
              credits: creditsForPack(validatedPack),
              invoiceId: session.id,
            });
          } else {
            console.warn(
              "topup checkout.session.completed without recognised price",
              { sessionId: session.id, priceId, metaPack: pack },
            );
          }
        }
        break;
      }

      case "customer.subscription.created":
      case "customer.subscription.updated":
      case "customer.subscription.deleted": {
        const sub = event.data.object as Stripe.Subscription;
        const customerId = typeof sub.customer === "string" ? sub.customer : sub.customer.id;
        const userId =
          (sub.metadata?.supabase_user_id as string | undefined) ??
          (await resolveUserForCustomer(customerId));
        if (!userId) {
          console.warn("No user found for subscription", sub.id);
          break;
        }
        await upsertSubscription(sub, userId);
        break;
      }

      case "invoice.paid": {
        const invoice = event.data.object as Stripe.Invoice;
        const customerId = typeof invoice.customer === "string" ? invoice.customer : invoice.customer?.id;
        if (!customerId) break;
        const userId = await resolveUserForCustomer(customerId);
        if (!userId) break;

        const priceId = invoice.lines.data[0]?.price?.id;
        const tier = tierFromPriceId(priceId);
        if (!tier) break;

        // For YEARLY subs we still only grant ONE month of credits up front.
        // The remaining 11 months are granted by the
        // /api/cron/grant-yearly-credits Vercel cron job (one per month).
        // This avoids a 2400-credit cost spike if a yearly subscriber
        // burns through everything and immediately churns.
        // The ref includes ":0" so the cron can use ":1"…":11" without
        // colliding with the up-front grant.
        const interval = intervalFromPriceId(priceId);
        const ref = interval === "year" ? `${invoice.id}:0` : invoice.id;

        await grantPeriodCredits({
          userId,
          tier,
          invoiceId: ref,
        });
        break;
      }

      default:
        // Unhandled event types are fine — just ack.
        break;
    }

    res.status(200).json({ received: true });
  } catch (err) {
    console.error("stripe-webhook handler error", err);
    res.status(500).json({ error: "Webhook handler failed" });
  }
}
