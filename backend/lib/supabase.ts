import { createClient, SupabaseClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL!;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

if (!url || !serviceRoleKey) {
  throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set");
}

/**
 * Server-side Supabase client using the service role key.
 * NEVER send this key to the browser or the app — it bypasses RLS.
 */
export const supabase: SupabaseClient = createClient(url, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

export type SubscriptionRow = {
  id: string;
  user_id: string;
  tier: "starter" | "plus" | "studio";
  status: string;
  monthly_credits: number;
  current_period_start: string;
  current_period_end: string;
  cancel_at_period_end: boolean;
};

/** Returns the user's active subscription (if any). */
export async function activeSubscription(userId: string): Promise<SubscriptionRow | null> {
  const { data, error } = await supabase
    .from("subscriptions")
    .select("*")
    .eq("user_id", userId)
    .in("status", ["active", "trialing", "past_due"])
    .order("current_period_end", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  return (data as SubscriptionRow | null) ?? null;
}

/** Returns remaining credits for the user's current period (0 if none). */
export async function currentCredits(userId: string): Promise<number> {
  const { data, error } = await supabase.rpc("current_credits", { p_user: userId });
  if (error) throw error;
  return typeof data === "number" ? data : 0;
}

/** Inserts a ledger entry. `delta` is positive for grants, negative for spends. */
export async function logCredit(opts: {
  userId: string;
  delta: number;
  reason: string;
  ref?: string;
}): Promise<void> {
  const { error } = await supabase.from("credit_ledger").insert({
    user_id: opts.userId,
    delta: opts.delta,
    reason: opts.reason,
    ref: opts.ref ?? null,
  });
  if (error) throw error;
}

/**
 * E14.9 — top a comped Pro account (CMS `pro-access`, mode "pro") up to its
 * monthly credit allowance.
 *
 * A comped account has no Stripe subscription, so nothing ever grants it
 * credits: the webhook's `invoice.paid` path is the only grant path for
 * paying users and it never fires here. Without this the account would show
 * tier "pro", pass every Pro gate, and then 402 on the first cloud action.
 *
 * Semantics are top-up, not stack: the first call in a calendar month raises
 * the balance TO `monthlyCredits`, it doesn't add `monthlyCredits` to it.
 * Stacking would let a dormant comped account accrue a year of unspent
 * credits and then spend them all at once — real Replicate money.
 *
 * Idempotency is the same shape as the Stripe topup grants: a deterministic
 * `ref` plus the partial unique index from sql/018. Two concurrent first-of-
 * the-month requests race; one insert wins, the loser gets 23505 and we
 * swallow it. The in-process memo means the balance lookup happens once per
 * account per month per warm instance, not on every request.
 *
 * Never throws — a failed grant must not take down the endpoint that called
 * it. The user hits the normal insufficient-credits path instead, which is
 * wrong but recoverable; a 500 is neither.
 */
const compedGrantMemo = new Set<string>();

export async function ensureCompedCredits(
  userId: string,
  monthlyCredits: number,
): Promise<void> {
  if (monthlyCredits <= 0) return;

  // Calendar month in UTC. Deliberately not the signup anniversary: a comp
  // list has no billing cycle to align to, and "resets on the 1st" is the
  // thing that's explainable to the person you comped.
  const now = new Date();
  const period = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
  const memoKey = `${userId}:${period}`;
  if (compedGrantMemo.has(memoKey)) return;

  try {
    // `credit_ledger.user_id` FKs `public.users`. Most endpoints call
    // `ensureUser` well after they resolve entitlements, so the row may not
    // exist yet on a comped account's first ever request — without this the
    // insert below dies on a FK violation and the user sees 0 credits.
    await ensureUser(userId);

    const balance = await currentCredits(userId);
    const delta = monthlyCredits - balance;
    if (delta <= 0) {
      // Already at or above the allowance — nothing to grant this month.
      compedGrantMemo.add(memoKey);
      return;
    }

    const { error } = await supabase.from("credit_ledger").insert({
      user_id: userId,
      delta,
      reason: "comped_pro",
      ref: `comped:${userId}:${period}`,
    });
    // 23505 = unique violation: another request already granted this month.
    if (error && error.code !== "23505") throw error;
    compedGrantMemo.add(memoKey);
  } catch (err) {
    console.error("[comped-pro] monthly grant failed", userId, period, err);
  }
}

/** Ensures a `public.users` row exists (mirrors auth.users). */
export async function ensureUser(userId: string): Promise<void> {
  const { error } = await supabase
    .from("users")
    .upsert({ id: userId }, { onConflict: "id" });
  if (error) throw error;
}

/**
 * Finds an `auth.users` row by email, or creates one with no password set.
 * Used by the Stripe webhook when an anonymous checkout completes — Stripe
 * captured the email, and we need a Supabase user to attach the
 * subscription / credits / device_grants to. The user can later sign in
 * with that email via Google OAuth or a magic link; Supabase deduplicates
 * by email so the auth row created here becomes their account.
 *
 * `email_confirm: true` skips Supabase's confirmation email — the email is
 * already trusted because Stripe verified it for billing.
 *
 * The lookup goes through the GoTrue admin API rather than a direct
 * `supabase.schema("auth").from("users")` query. PostgREST blocks the
 * `auth` schema unless it's explicitly added to the project's exposed
 * schemas list; service-role bypasses RLS but NOT the schema gate
 * (PGRST106). The admin API is the supported, schema-exposure-independent
 * path.
 */
export async function findUserIdByEmail(email: string): Promise<string | null> {
  const target = email.trim().toLowerCase();
  for (let page = 1; ; page++) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    const hit = data.users.find((u) => u.email?.toLowerCase() === target);
    if (hit) return hit.id;
    if (data.users.length < 200) return null;
  }
}

export async function findOrCreateUserByEmail(email: string): Promise<string> {
  const normalized = email.trim().toLowerCase();

  const existingId = await findUserIdByEmail(normalized);
  if (existingId) return existingId;

  const { data: created, error: createErr } = await supabase.auth.admin.createUser({
    email: normalized,
    email_confirm: true,
  });
  if (createErr) throw createErr;
  if (!created.user?.id) throw new Error("createUser returned no user id");
  return created.user.id;
}

/**
 * Generates a Supabase magic-link for `email` and returns the action URL.
 * Caller is responsible for delivering the link (we don't auto-send so we
 * don't spam users — the link is surfaced via the in-app
 * `/v1/account/resend-magic-link` endpoint which does email it through
 * Supabase SMTP via signInWithOtp).
 */
export async function generateMagicLink(email: string): Promise<string> {
  const redirectTo = `${process.env.APP_URL_SCHEME ?? "aaavatar"}://auth-callback`;
  const { data, error } = await supabase.auth.admin.generateLink({
    type: "magiclink",
    email: email.trim().toLowerCase(),
    options: { redirectTo },
  });
  if (error) throw error;
  const link = data?.properties?.action_link;
  if (!link) throw new Error("generateLink returned no action_link");
  return link;
}

/**
 * Free-tier Magic Cutout trial allowance. Free accounts get this many
 * BiRefNet cutouts before they need to subscribe (or fall back to the
 * basic Subject Lift). Enforced server-side so reinstalling the app
 * can't reset the counter.
 */
export const FREE_CUTOUTS_ALLOWANCE = 3;

/** Returns how many free Magic Cutout calls this user has spent so far. */
export async function freeCutoutsUsed(userId: string): Promise<number> {
  const { data, error } = await supabase
    .from("users")
    .select("free_cutouts_used")
    .eq("id", userId)
    .maybeSingle();
  if (error) throw error;
  const used = (data as { free_cutouts_used: number } | null)?.free_cutouts_used;
  return typeof used === "number" ? used : 0;
}

/**
 * Atomically claims one free-trial cutout slot. Returns the new count on
 * success, or null when the user has already exhausted the allowance.
 * Single-statement UPDATE inside the SQL function (see migration 003) is
 * the race-safe gate.
 */
export async function tryConsumeFreeCutout(userId: string): Promise<number | null> {
  const { data, error } = await supabase.rpc("try_consume_free_cutout", {
    p_user: userId,
    p_allowance: FREE_CUTOUTS_ALLOWANCE,
  });
  if (error) throw error;
  return typeof data === "number" ? data : null;
}

/**
 * Lifetime free-tier import allowance. Enforced as "3 imports ever", not
 * "3 portraits at a time" — deleting a portrait does not free a slot.
 * Source-agnostic: a free import can be Subject Lift OR Magic Cutout,
 * both count the same. Mirrored client-side in `FreeTier.maxPortraits`.
 */
export const FREE_IMPORTS_ALLOWANCE = 3;

export type ImportClaimResult = {
  allowed: boolean;
  userUsed: number;
  deviceUsed: number;
  allowance: number;
};

/**
 * Atomic anti-cheat gate for free-tier imports. Pass `userId = null` for
 * anonymous (signed-out) callers — only the device counter is consulted.
 * The SQL function (see migration 004) increments both counters in a
 * single statement; concurrent calls cannot push past the cap.
 */
export async function tryConsumeFreeImport(
  userId: string | null,
  fingerprint: string,
): Promise<ImportClaimResult> {
  const { data, error } = await supabase.rpc("try_consume_free_import", {
    p_user: userId,
    p_fingerprint: fingerprint,
    p_allowance: FREE_IMPORTS_ALLOWANCE,
  });
  if (error) throw error;
  const obj = (data ?? {}) as Record<string, unknown>;
  return {
    allowed: obj.allowed === true,
    userUsed: typeof obj.user_used === "number" ? obj.user_used : 0,
    deviceUsed: typeof obj.device_used === "number" ? obj.device_used : 0,
    allowance: typeof obj.allowance === "number"
      ? obj.allowance
      : FREE_IMPORTS_ALLOWANCE,
  };
}

/** Read-only: how many lifetime free imports this user has consumed. */
export async function freeImportsUsedForUser(userId: string): Promise<number> {
  const { data, error } = await supabase
    .from("users")
    .select("free_imports_used")
    .eq("id", userId)
    .maybeSingle();
  if (error) throw error;
  const used = (data as { free_imports_used: number } | null)?.free_imports_used;
  return typeof used === "number" ? used : 0;
}
