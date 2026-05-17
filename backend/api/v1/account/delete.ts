import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireUser } from "../../../lib/auth.js";
import { stripe } from "../../../lib/stripe.js";
import { supabase } from "../../../lib/supabase.js";

/**
 * DELETE /v1/account
 *
 * GDPR Art. 17 right-to-erasure endpoint (audit ISO/SOC + GDPR readiness
 * gap). The caller authenticates as the user being deleted; the JWT in
 * the bearer header is the consent signal.
 *
 * Required header:
 *   Authorization: Bearer <supabase access token>
 *   X-Confirm-Delete: yes              — second consent, blocks
 *                                        accidental DELETEs from buggy
 *                                        clients hitting the wrong path
 *
 * Returns:
 *   200 { deleted: true, scope: { … } }
 *   401 invalid / missing token
 *   400 missing confirmation header
 *   500 internal — caller should retry; the operation is idempotent
 *
 * Wipe order (each step is best-effort, errors are collected — we'd
 * rather leave a dangling row than fail mid-deletion and leave the user
 * unable to retry):
 *   1. Cancel any active Stripe subscriptions immediately. Cannot delete
 *      the Stripe customer record — Dutch tax law (and Stripe's own
 *      retention policy) requires invoice records to live ~7 years.
 *      Cancellation stops future billing; stored data is the legitimate
 *      legal-basis carve-out documented in the privacy policy.
 *   2. Wipe the user's prefix in the `cutout-uploads` Supabase Storage
 *      bucket. These are short-lived (5-min signed URLs) so most users
 *      have an empty prefix, but a crashed cutout could leave dangling
 *      bytes.
 *   3. Delete the Supabase Auth user via the GoTrue admin API. The FK
 *      cascade from `auth.users → public.users` then takes care of
 *      `subscriptions`, `credit_ledger`, `device_imports`,
 *      `device_grants`, `device_user_merges` in one transaction.
 *
 * Note: Payload's `newsletter-unsubscribes` collection is intentionally
 * NOT cleared — a user who asked to be unsubscribed and then closes
 * their account should stay unsubscribed if they ever sign up again.
 * `audit_log` (if/when MEDIUM #24 lands) similarly retains hashes only.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "DELETE" && req.method !== "POST") {
    // Accept POST too because some HTTP clients (URLSession with auth
    // tokens, in particular) treat DELETE with body inconsistently.
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const confirm = req.headers["x-confirm-delete"];
  if (confirm !== "yes") {
    res.status(400).json({ error: "missing_confirmation_header" });
    return;
  }

  const user = await requireUser(req, res);
  if (!user) return;

  const scope: {
    stripe_subscriptions_cancelled: number;
    stripe_customer_kept: boolean;
    storage_objects_removed: number;
    auth_user_deleted: boolean;
    errors: string[];
  } = {
    stripe_subscriptions_cancelled: 0,
    stripe_customer_kept: false,
    storage_objects_removed: 0,
    auth_user_deleted: false,
    errors: [],
  };

  // 1. Cancel any active Stripe subscriptions before tearing down the
  //    local linkage. Read the customer id off `public.users` because
  //    that's where the webhook stamps it.
  try {
    const { data: row } = await supabase
      .from("users")
      .select("stripe_customer_id")
      .eq("id", user.id)
      .maybeSingle();
    const customerId = (row?.stripe_customer_id as string | undefined) ?? null;
    if (customerId) {
      scope.stripe_customer_kept = true;
      const subs = await stripe.subscriptions.list({
        customer: customerId,
        status: "all",
        limit: 100,
      });
      for (const sub of subs.data) {
        if (sub.status === "canceled" || sub.status === "incomplete_expired") continue;
        try {
          await stripe.subscriptions.cancel(sub.id);
          scope.stripe_subscriptions_cancelled += 1;
        } catch (err) {
          scope.errors.push(`stripe_cancel_${sub.id}: ${(err as Error).message}`);
        }
      }
    }
  } catch (err) {
    scope.errors.push(`stripe_lookup: ${(err as Error).message}`);
  }

  // 2. Sweep the cutout-uploads bucket prefix. Errors here are
  //    non-fatal — orphaned bytes age out via Supabase's bucket TTL.
  try {
    const { data: objects, error: listErr } = await supabase.storage
      .from("cutout-uploads")
      .list(user.id, { limit: 1000 });
    if (listErr) throw listErr;
    if (objects && objects.length > 0) {
      const paths = objects.map((o) => `${user.id}/${o.name}`);
      const { error: rmErr } = await supabase.storage.from("cutout-uploads").remove(paths);
      if (rmErr) throw rmErr;
      scope.storage_objects_removed = paths.length;
    }
  } catch (err) {
    scope.errors.push(`storage_wipe: ${(err as Error).message}`);
  }

  // 3. Delete the auth user. The FK cascade does the rest.
  try {
    const { error: delErr } = await supabase.auth.admin.deleteUser(user.id);
    if (delErr) throw delErr;
    scope.auth_user_deleted = true;
  } catch (err) {
    scope.errors.push(`auth_delete: ${(err as Error).message}`);
    // If the auth delete failed, the user can retry. Report failure
    // so the client surfaces it loudly instead of pretending success.
    res.status(500).json({ deleted: false, scope });
    return;
  }

  res.status(200).json({ deleted: true, scope });
}
