import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireUser } from "../../lib/auth.js";
import {
  activeSubscription,
  currentCredits,
  ensureUser,
  freeCutoutsUsed,
  freeImportsUsedForUser,
  FREE_CUTOUTS_ALLOWANCE,
  FREE_IMPORTS_ALLOWANCE,
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
  const user = await requireUser(req, res);
  if (!user) return;

  try {
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
    });
  } catch (err) {
    console.error("/v1/account error", err);
    res.status(500).json({ error: "Internal error" });
  }
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
