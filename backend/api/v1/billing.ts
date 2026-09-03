import type { VercelRequest, VercelResponse } from "@vercel/node";
import type Stripe from "stripe";
import { requireUser } from "../../lib/auth.js";
import {
  mapInvoices,
  mapSubscription,
  pickCurrentSubscription,
  type BillingPayload,
  type UpcomingLike,
} from "../../lib/billing.js";
import { supabase } from "../../lib/supabase.js";
import { stripe } from "../../lib/stripe.js";

/**
 * GET /v1/billing
 *
 * Settings › Billing & Invoices. Reads the signed-in user's Stripe customer
 * and returns the current plan (list price, discount, next charge) plus the
 * invoice history — enough to render the page in-app without opening the
 * Customer Portal (`/v1/portal` stays the write path: payment method,
 * cancel, tax ids).
 *
 * Returns: 200 BillingPayload — `plan: null, invoices: []` when the user has
 *          no Stripe customer yet (Starter, or a Pro comp without billing).
 *          401 / 405 / 500
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET") {
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
      const empty: BillingPayload = { plan: null, invoices: [] };
      res.status(200).json(empty);
      return;
    }

    const [subs, invoices] = await Promise.all([
      stripe.subscriptions.list({
        customer: customerId,
        status: "all",
        limit: 10,
        expand: ["data.discounts"],
      }),
      stripe.invoices.list({ customer: customerId, limit: 24 }),
    ]);

    const current = pickCurrentSubscription(subs.data);
    let upcoming: UpcomingLike = null;
    if (current && !current.cancel_at_period_end) {
      // Best-effort: Stripe 404s the preview when nothing is scheduled
      // (e.g. a trial ending in cancellation). The Plan card then simply
      // omits the "Next payment" row.
      try {
        const preview = await stripe.invoices.retrieveUpcoming({
          customer: customerId,
          subscription: current.id,
        });
        upcoming = { amount_due: preview.amount_due, currency: preview.currency };
      } catch (err) {
        console.warn("/v1/billing upcoming preview unavailable", {
          subscriptionId: current.id,
          message: (err as Stripe.errors.StripeError)?.message,
        });
      }
    }

    const payload: BillingPayload = {
      plan: current ? mapSubscription(current, upcoming) : null,
      invoices: mapInvoices(invoices.data),
    };
    res.status(200).json(payload);
  } catch (err) {
    console.error("/v1/billing error", err);
    res.status(500).json({ error: "billing_failed" });
  }
}
