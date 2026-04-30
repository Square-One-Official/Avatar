import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireUser } from "../../lib/auth.js";
import { supabase } from "../../lib/supabase.js";
import { stripe } from "../../lib/stripe.js";

const APP_SCHEME = process.env.APP_URL_SCHEME ?? "aaavatar";

/**
 * POST /v1/portal
 *
 * Creates a Stripe Customer Portal session for the authenticated user. The
 * portal lets users update payment method, view invoices, and cancel their
 * subscription — required so Pro subscribers can self-serve cancellation
 * instead of emailing support.
 *
 * Returns: 200 { url: string } — hosted Stripe Billing Portal URL
 *          404 { error: "no_customer" } — user has no Stripe customer yet
 *          401 / 500
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const user = await requireUser(req, res);
  if (!user) return;

  try {
    const { data: row } = await supabase
      .from("users")
      .select("stripe_customer_id")
      .eq("id", user.id)
      .maybeSingle();

    const customerId = row?.stripe_customer_id as string | undefined;
    if (!customerId) {
      res.status(404).json({ error: "no_customer" });
      return;
    }

    const session = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: `${APP_SCHEME}://stripe-return`,
    });

    res.status(200).json({ url: session.url });
  } catch (err) {
    console.error("/v1/portal error", err);
    res.status(500).json({ error: "portal_failed" });
  }
}
