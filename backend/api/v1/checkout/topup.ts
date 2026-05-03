import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireUser } from "../../../lib/auth.js";
import { sendCheckoutError } from "../../../lib/checkout-errors.js";
import { activeSubscription, ensureUser, supabase } from "../../../lib/supabase.js";
import { isCreditPack, priceIdForPack, stripe, type CreditPack } from "../../../lib/stripe.js";

const APP_SCHEME = process.env.APP_URL_SCHEME ?? "aaavatar";

/**
 * POST /v1/checkout/topup
 *
 * Body:    { pack: "credits50" | "credits200" | "credits750" }
 *           Pricing ladder (see lib/stripe.ts):
 *             credits50  €1,99  →  50 credits  (impulse)
 *             credits200 €4,99  → 200 credits  (standard, anchor middle)
 *             credits750 €14,99 → 750 credits  (best value, ~20% extra)
 * Returns: 200 { url: string } — hosted Stripe Checkout URL (DMG build path)
 *          200 { storekit_product_id: string } — App Store build (deferred)
 *          400 { error: "invalid_pack" }
 *          401 / 500
 *
 * Top-up packs are one-time purchases. Credits are granted by the
 * stripe-webhook handler when the corresponding `invoice.paid` event
 * arrives, with `(reason='topup_pack', ref=<invoice id>)` for idempotency.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const user = await requireUser(req, res);
  if (!user) return;

  const rawPack = (req.body as { pack?: unknown } | null | undefined)?.pack;
  if (!isCreditPack(rawPack)) {
    res.status(400).json({ error: "invalid_pack" });
    return;
  }
  const pack: CreditPack = rawPack;

  // Top-ups are only sold to active subscribers — credits are useless without
  // Pro since the gated feature (Magic Cutout) requires it.
  // Grace-period subs (past_due) are allowed by activeSubscription().
  // Dev-allowlisted users bypass the gate so they can exercise the full
  // Stripe Checkout flow even though they have no real subscription row.
  await ensureUser(user.id);
  if (!isDevUnlimitedUser(user.email)) {
    const sub = await activeSubscription(user.id);
    if (!sub) {
      res.status(403).json({ error: "pro_required" });
      return;
    }
  }

  const priceId = priceIdForPack(pack);
  if (!priceId) {
    console.error(`/v1/checkout/topup: price ID for ${pack} is not configured`);
    res.status(500).json({ error: "pricing_misconfigured" });
    return;
  }

  try {
    const { data: existing } = await supabase
      .from("users")
      .select("stripe_customer_id")
      .eq("id", user.id)
      .maybeSingle();

    let customerId = existing?.stripe_customer_id as string | null | undefined;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        metadata: { supabase_user_id: user.id },
      });
      customerId = customer.id;
      await supabase
        .from("users")
        .update({ stripe_customer_id: customerId })
        .eq("id", user.id);
    }

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      customer: customerId,
      line_items: [{ price: priceId, quantity: 1 }],
      success_url: `${APP_SCHEME}://stripe-return`,
      cancel_url: `${APP_SCHEME}://stripe-cancel`,
      allow_promotion_codes: true,
      automatic_tax: { enabled: true },
      // Stripe Tax needs an address; persist whatever the user enters in
      // Checkout back onto the Customer (see subscribe.ts for rationale).
      customer_update: { address: "auto" },
      // Tagged so the webhook can recognise topup invoices and grant credits.
      payment_intent_data: {
        metadata: { supabase_user_id: user.id, pack, flow: "topup" },
      },
      metadata: { supabase_user_id: user.id, pack, flow: "topup" },
    });

    res.status(200).json({ url: session.url });
  } catch (err) {
    sendCheckoutError(req, res, "/v1/checkout/topup", err);
  }
}

function isDevUnlimitedUser(email: string | null | undefined): boolean {
  if (!email) return false;
  const list = (process.env.DEV_UNLIMITED_EMAILS ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  return list.includes(email.toLowerCase());
}
