import type { VercelRequest, VercelResponse } from "@vercel/node";
import { optionalUser } from "../../lib/auth.js";
import {
  activeSubscription,
  currentCredits,
  ensureUser,
  freeCutoutsUsed,
  freeImportsUsedForUser,
  FREE_CUTOUTS_ALLOWANCE,
  FREE_IMPORTS_ALLOWANCE,
  supabase,
} from "../../lib/supabase.js";
import { creditsForTier, type Tier } from "../../lib/stripe.js";

/**
 * GET /v1/account
 *
 * Drives `ProEntitlement` on the client. Snake_case keys are decoded by the
 * client's JSONDecoder via `.convertFromSnakeCase`.
 *
 * Response shape:
 * {
 *   tier: "free" | "pro" | null,            // null is treated as free by the client
 *   credits_remaining: int,                  // monthly grant + unspent topups
 *   monthly_quota: int,                      // 200 for pro, 0 for free
 *   monthly_reset_at: iso8601 | null,        // when the monthly grant resets
 *   subscription_status: "active"|"lapsed"|"none",
 *   subscription_renews_at: iso8601 | null,  // distinct from monthly_reset; for pro both are the same date
 *   free_cutouts_used: int,                  // Magic Cutout free-trial calls spent (0..FREE_CUTOUTS_ALLOWANCE)
 *   free_cutouts_remaining: int,             // FREE_CUTOUTS_ALLOWANCE - used, clamped at 0
 *   free_imports_used: int,                  // Lifetime imports spent (0..FREE_IMPORTS_ALLOWANCE)
 *   free_imports_remaining: int              // FREE_IMPORTS_ALLOWANCE - used, clamped at 0
 * }
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  // Three states this endpoint serves:
  //   1. Signed-in user (Bearer token valid)         → full account payload.
  //   2. Signed-out + device has a paid checkout grant
  //      (`device_grants` row matches X-Device-Fingerprint) →
  //      Pro payload + needs_account_link=true so the UI shows the
  //      "sign in to sync across Macs" banner.
  //   3. Signed-out + no device grant                 → free-tier payload.
  //
  // Anonymous mode replaces the previous 401 hard-fail; pre-auth checkout
  // makes it possible to be Pro without a Supabase session yet.
  const userResult = await optionalUser(req, res);
  if (userResult === "rejected") return; // optionalUser already wrote 401

  try {
    if (userResult) {
      const user = userResult;
      await ensureUser(user.id);

      // Dev-allowlisted users impersonate Pro state without an actual Stripe
      // subscription. Mirrors the bypass in /v1/cutout so
      // the client unlocks every Pro-gated UI path. Quota uses a high sentinel
      // so the UI doesn't surface a paywall on the first cutout call.
      if (isDevUnlimitedUser(user.email)) {
        res.status(200).json({
          tier: "pro",
          credits_remaining: 999_999,
          monthly_quota: 999_999,
          monthly_reset_at: null,
          subscription_status: "active",
          subscription_renews_at: null,
          free_cutouts_used: 0,
          free_cutouts_remaining: FREE_CUTOUTS_ALLOWANCE,
          free_imports_used: 0,
          free_imports_remaining: FREE_IMPORTS_ALLOWANCE,
          needs_account_link: false,
        });
        return;
      }

      const [sub, credits, freeCutouts, freeImports] = await Promise.all([
        activeSubscription(user.id),
        currentCredits(user.id),
        freeCutoutsUsed(user.id),
        freeImportsUsedForUser(user.id),
      ]);

      const tier = mapTierForClient(sub?.tier);
      const monthlyQuota = sub ? quotaForRawTier(sub.tier) : 0;
      const subscriptionStatus = mapSubscriptionStatus(sub?.status);
      const periodEnd = sub?.current_period_end ?? null;

      res.status(200).json({
        tier,
        credits_remaining: credits,
        monthly_quota: monthlyQuota,
        monthly_reset_at: periodEnd,
        subscription_status: subscriptionStatus,
        subscription_renews_at: periodEnd,
        free_cutouts_used: freeCutouts,
        free_cutouts_remaining: Math.max(0, FREE_CUTOUTS_ALLOWANCE - freeCutouts),
        free_imports_used: freeImports,
        free_imports_remaining: Math.max(0, FREE_IMPORTS_ALLOWANCE - freeImports),
        needs_account_link: false,
      });
      return;
    }

    // Anonymous path. Look up device_grants by fingerprint; if present, the
    // device has a paid Pro grant from a pre-auth checkout. Resolve the
    // account that owns the grant and serve a Pro payload tagged
    // `needs_account_link: true`.
    const fingerprint = req.headers["x-device-fingerprint"];
    if (typeof fingerprint === "string" && fingerprint) {
      const { data: grant } = await supabase
        .from("device_grants")
        .select("user_id")
        .eq("device_fingerprint", fingerprint)
        .maybeSingle();

      const grantedUserId = (grant?.user_id as string | undefined) ?? null;
      if (grantedUserId) {
        const [sub, credits, freeCutouts, freeImports] = await Promise.all([
          activeSubscription(grantedUserId),
          currentCredits(grantedUserId),
          freeCutoutsUsed(grantedUserId),
          freeImportsUsedForUser(grantedUserId),
        ]);

        const grantedEmail = await emailForUser(grantedUserId);
        const tier = mapTierForClient(sub?.tier);
        const monthlyQuota = sub ? quotaForRawTier(sub.tier) : 0;
        const subscriptionStatus = mapSubscriptionStatus(sub?.status);
        const periodEnd = sub?.current_period_end ?? null;

        res.status(200).json({
          tier,
          credits_remaining: credits,
          monthly_quota: monthlyQuota,
          monthly_reset_at: periodEnd,
          subscription_status: subscriptionStatus,
          subscription_renews_at: periodEnd,
          free_cutouts_used: freeCutouts,
          free_cutouts_remaining: Math.max(0, FREE_CUTOUTS_ALLOWANCE - freeCutouts),
          free_imports_used: freeImports,
          free_imports_remaining: Math.max(0, FREE_IMPORTS_ALLOWANCE - freeImports),
          needs_account_link: true,
          link_email: grantedEmail,
        });
        return;
      }
    }

    // Pure anonymous: no signed-in user and no device grant. Free tier.
    res.status(200).json({
      tier: null,
      credits_remaining: 0,
      monthly_quota: 0,
      monthly_reset_at: null,
      subscription_status: "none",
      subscription_renews_at: null,
      free_cutouts_used: 0,
      free_cutouts_remaining: FREE_CUTOUTS_ALLOWANCE,
      free_imports_used: 0,
      free_imports_remaining: FREE_IMPORTS_ALLOWANCE,
      needs_account_link: false,
    });
  } catch (err) {
    console.error("/v1/account error", err);
    res.status(500).json({ error: "Internal error" });
  }
}

/**
 * Look up email of an auth.users row by id via the GoTrue admin API.
 * Direct `supabase.schema("auth").from("users")` queries are blocked by
 * PostgREST (PGRST106 — auth is not in the exposed-schemas list); service
 * role bypasses RLS but not the schema gate.
 */
async function emailForUser(userId: string): Promise<string | null> {
  const { data, error } = await supabase.auth.admin.getUserById(userId);
  if (error) {
    console.warn("emailForUser failed", error);
    return null;
  }
  return data.user?.email ?? null;
}

/**
 * Collapse the legacy starter/plus/studio tiers to "pro" for the client.
 * The v1 client only knows "free" | "pro" but we still store the original
 * tier server-side for billing accuracy.
 */
function mapTierForClient(tier: string | null | undefined): "pro" | null {
  if (!tier) return null;
  return "pro";
}

/**
 * Validate a raw DB tier string and return its monthly credit grant. Returns
 * 0 for unknown values rather than letting an unconstrained `as Tier` cast
 * fall through to NaN-like behavior in `creditsForTier`. The
 * `subscriptions_tier_check` SQL constraint already restricts the column,
 * but this guard keeps a future schema change from silently lying to clients.
 */
function quotaForRawTier(tier: string | null | undefined): number {
  if (tier === "starter" || tier === "plus" || tier === "studio" || tier === "pro") {
    return creditsForTier(tier as Tier);
  }
  return 0;
}

/**
 * Map Stripe subscription status → the three-state enum the client uses.
 *  - active / trialing → "active"
 *  - past_due / unpaid / incomplete → "lapsed" (still has access during grace)
 *  - cancelled / null / anything else → "none"
 */
function mapSubscriptionStatus(
  status: string | null | undefined,
): "active" | "lapsed" | "none" {
  if (!status) return "none";
  if (status === "active" || status === "trialing") return "active";
  if (status === "past_due" || status === "unpaid" || status === "incomplete") return "lapsed";
  return "none";
}

/**
 * True when the caller's e-mail is on the DEV_UNLIMITED_EMAILS allowlist.
 * Same comma-separated env var honored by /v1/cutout.
 */
function isDevUnlimitedUser(email: string | null | undefined): boolean {
  if (!email) return false;
  const list = (process.env.DEV_UNLIMITED_EMAILS ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  return list.includes(email.toLowerCase());
}
