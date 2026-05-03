import type { VercelRequest, VercelResponse } from "@vercel/node";
import { sendCheckoutError } from "../../../lib/checkout-errors.js";
import { isSubscriptionInterval, priceIdForTier, stripe } from "../../../lib/stripe.js";

const APP_SCHEME = process.env.APP_URL_SCHEME ?? "aaavatar";

/**
 * POST /v1/checkout/subscribe-anonymous
 *
 * Pre-auth checkout — the user does NOT need a Supabase session yet. Stripe
 * collects the email during checkout, and the webhook (see
 * `stripe-webhook.ts → checkout.session.completed`) creates / finds the
 * Supabase user, links the Stripe customer, and stores a `device_grants`
 * row so the macOS app can recognise this Mac as Pro on subsequent
 * `/v1/account` calls without ever asking the user to sign in.
 *
 * Body:
 *   { interval?: "month" | "year" }  — defaults to "month".
 *
 * Required header:
 *   X-Device-Fingerprint  — sent by every BackendClient request. We pass it
 *   to Stripe as `client_reference_id` and on metadata so the webhook can
 *   write the device_grants row keyed on the same value.
 *
 * Returns:
 *   200 { url: string }                      — hosted Stripe Checkout URL
 *   400 { error: "invalid_interval" }         — bad body
 *   400 { error: "missing_device_fingerprint" }
 *   500 { error: "pricing_misconfigured" }    — env vars
 *   502 { error: "stripe_unavailable" | "checkout_init_failed", requestId }
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const fingerprint = req.headers["x-device-fingerprint"];
  if (typeof fingerprint !== "string" || !fingerprint) {
    res.status(400).json({ error: "missing_device_fingerprint" });
    return;
  }

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
    console.error(`/v1/checkout/subscribe-anonymous: ${envName} is not configured`);
    res.status(500).json({ error: "pricing_misconfigured" });
    return;
  }

  try {
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      // No `customer` — subscription mode always creates one, captures the
      // email in checkout, and persists whatever address the user enters so
      // Stripe Tax has what it needs. (`customer_creation` is rejected in
      // subscription mode — auto-creation is the default behaviour.)
      client_reference_id: fingerprint,
      line_items: [{ price: proPriceId, quantity: 1 }],
      success_url: `${APP_SCHEME}://stripe-return?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${APP_SCHEME}://stripe-cancel`,
      allow_promotion_codes: true,
      automatic_tax: { enabled: true },
      subscription_data: {
        metadata: {
          tier: "pro",
          interval,
          device_fingerprint: fingerprint,
          flow: "subscribe_anonymous",
        },
      },
      metadata: {
        tier: "pro",
        interval,
        device_fingerprint: fingerprint,
        flow: "subscribe_anonymous",
      },
    });

    res.status(200).json({ url: session.url });
  } catch (err) {
    sendCheckoutError(req, res, "/v1/checkout/subscribe-anonymous", err);
  }
}
