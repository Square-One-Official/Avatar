import { timingSafeEqual } from "node:crypto";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import {
  creditsForTier,
  resolvePriceLive,
  stripe,
} from "../../lib/stripe.js";
import { supabase } from "../../lib/supabase.js";

/**
 * GET /api/cron/grant-yearly-credits
 *
 * Vercel-cron endpoint. Runs on the 1st of every month (see vercel.json
 * `crons` section). For each ACTIVE yearly Pro subscription, computes
 * which "month index" we're currently in since `current_period_start`
 * (1..11; the initial month, index 0, was granted up-front by
 * stripe-webhook on `invoice.paid`) and inserts a credit_ledger entry
 * with ref `<invoice_id>:<monthIndex>`.
 *
 * The unique-on-ref index makes the insert idempotent: if the cron runs
 * twice in the same month, or backfills a previously-missed month, the
 * second insert is a no-op.
 *
 * Auth: protected by CRON_SECRET via Authorization header
 *       (Vercel sets this automatically for cron requests; manual hits
 *       must include `Authorization: Bearer <CRON_SECRET>`).
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  // Vercel cron sends `Authorization: Bearer <CRON_SECRET>` automatically.
  const expected = process.env.CRON_SECRET;
  if (!expected) {
    console.error("CRON_SECRET not configured");
    res.status(500).json({ error: "cron_misconfigured" });
    return;
  }
  const authHeader = req.headers.authorization;
  const auth = Array.isArray(authHeader) ? authHeader[0] : authHeader;
  if (!isAuthorized(auth, expected)) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  let processed = 0;
  let granted = 0;
  let skipped = 0;
  const errors: string[] = [];

  try {
    // Fetch active subscriptions from our mirror. We then call Stripe to
    // get the actual price ID and verify the interval — our local row
    // doesn't store interval today.
    const { data: subs, error } = await supabase
      .from("subscriptions")
      .select("id, user_id, status, current_period_start, current_period_end")
      .in("status", ["active", "trialing", "past_due"]);
    if (error) throw error;

    for (const row of subs ?? []) {
      processed++;
      try {
        const sub = await stripe.subscriptions.retrieve(row.id);
        const priceId = sub.items.data[0]?.price.id;
        const resolved = await resolvePriceLive(priceId);
        if (!resolved || resolved.interval !== "year" || !resolved.tier) {
          skipped++;
          continue;
        }
        const tier = resolved.tier;

        // Find the most recent paid invoice for this subscription — its
        // ID is the ledger ref base used by the webhook.
        const invoices = await stripe.invoices.list({
          subscription: row.id,
          status: "paid",
          limit: 1,
        });
        const invoice = invoices.data[0];
        if (!invoice) {
          skipped++;
          continue;
        }

        const periodStartMs = sub.current_period_start * 1000;
        const monthIndex = monthsBetween(new Date(periodStartMs), new Date());
        // monthIndex 0 = up-front grant by webhook; cron only handles 1..11
        if (monthIndex < 1 || monthIndex > 11) {
          skipped++;
          continue;
        }

        const ref = `${invoice.id}:${monthIndex}`;
        const { error: insertErr } = await supabase.from("credit_ledger").insert({
          user_id: row.user_id,
          delta: creditsForTier(tier),
          reason: "period_renewal",
          ref,
        });
        if (insertErr) {
          if (/duplicate key/i.test(insertErr.message)) {
            // Already granted for this month — idempotent no-op.
            skipped++;
          } else {
            throw insertErr;
          }
        } else {
          granted++;
        }
      } catch (subErr) {
        errors.push(`${row.id}: ${(subErr as Error).message}`);
      }
    }

    res.status(200).json({ processed, granted, skipped, errors });
  } catch (err) {
    console.error("/api/cron/grant-yearly-credits error", err);
    res.status(500).json({ error: "cron_failed", message: (err as Error).message });
  }
}

/**
 * Constant-time bearer-token check (audit HIGH #5). The previous
 * implementation used `auth !== `Bearer ${expected}`` which short-circuits
 * at the first mismatched byte and is a textbook side-channel for
 * brute-forcing a long secret a byte at a time. `timingSafeEqual` requires
 * equal-length buffers, so we length-check first; the length of the
 * expected secret is not itself a secret (it's a Vercel-config artifact).
 */
function isAuthorized(received: string | undefined, expected: string): boolean {
  if (typeof received !== "string") return false;
  const expectedHeader = `Bearer ${expected}`;
  if (received.length !== expectedHeader.length) return false;
  const a = Buffer.from(received);
  const b = Buffer.from(expectedHeader);
  return timingSafeEqual(a, b);
}

/** Whole-month difference between two dates (calendar months, not 30-day blocks). */
function monthsBetween(start: Date, now: Date): number {
  const years = now.getUTCFullYear() - start.getUTCFullYear();
  const months = now.getUTCMonth() - start.getUTCMonth();
  let total = years * 12 + months;
  // If we're earlier in the month than start, we haven't crossed the
  // anniversary day yet — back up one month.
  if (now.getUTCDate() < start.getUTCDate()) total -= 1;
  return Math.max(0, total);
}
