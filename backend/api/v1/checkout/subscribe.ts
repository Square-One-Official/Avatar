import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireUser } from "../../../lib/auth.js";
import { ensureUser, supabase } from "../../../lib/supabase.js";
import { isSubscriptionInterval, priceIdForTier, stripe } from "../../../lib/stripe.js";

const APP_SCHEME = process.env.APP_URL_SCHEME ?? "aaavatar";

/**
 * POST /v1/checkout/subscribe
 *
 * Body:    { interval?: "month" | "year" } — billing cadence. Defaults to
 *               "month" when omitted (back-compat with v1 clients that
 *               don't yet send the field). Yearly Pro is €49,90 (17%
 *               cheaper, "2 months free"). Monthly stays €4,99.
 * Returns: 200 { url: string } — hosted Stripe Checkout URL (DMG build path)
 *          200 { storekit_product_id: string } — App Store build path (deferred)
 *          400 / 401 / 500
 *
 * Note: only one of `url` / `storekit_product_id` is set. The DMG build will
 * always get a `url`. The App Store build (later) will get a product id and
 * complete the purchase via StoreKit 2; the backend grants credits via the
 * App Store Server Notification.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const user = await requireUser(req, res);
  if (!user) return;

  // Parse + default the interval. Older clients that POST {} get monthly.
  const rawInterval = (req.body as { interval?: unknown } | null | undefined)?.interval;
  const interval = rawInterval === undefined
    ? "month"
    : isSubscriptionInterval(rawInterval) ? rawInterval : null;
  if (interval === null) {
    res.status(400).json({ error: "invalid_interval" });
    return;
  }

  const proPriceId = priceIdForTier("pro", interval);
  if (!proPriceId) {
    const envName = interval === "year" ? "PRICE_ID_PRO_ANNUAL" : "PRICE_ID_PRO";
    console.error(`/v1/checkout/subscribe: ${envName} is not configured`);
    res.status(500).json({ error: "pricing_misconfigured" });
    return;
  }

  try {
    await ensureUser(user.id);

    // Reuse an existing Stripe customer if we've created one.
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
      mode: "subscription",
      customer: customerId,
      line_items: [{ price: proPriceId, quantity: 1 }],
      success_url: `${APP_SCHEME}://stripe-return`,
      cancel_url: `${APP_SCHEME}://stripe-cancel`,
      allow_promotion_codes: true,
      automatic_tax: { enabled: true },
      // Stripe Tax needs an address; persist whatever the user enters in
      // Checkout back onto the Customer so subsequent sessions don't ask
      // again. Without this Stripe rejects the session with
      // `customer_tax_location_invalid`.
      customer_update: { address: "auto" },
      subscription_data: {
        metadata: { supabase_user_id: user.id, tier: "pro", interval },
      },
      metadata: {
        supabase_user_id: user.id,
        tier: "pro",
        interval,
        flow: "subscribe",
      },
    });

    res.status(200).json({ url: session.url });
  } catch (err) {
    console.error("/v1/checkout/subscribe error", err);
    res.status(500).json({ error: "checkout_failed" });
  }
}
