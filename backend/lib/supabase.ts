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

/** Ensures a `public.users` row exists (mirrors auth.users). */
export async function ensureUser(userId: string): Promise<void> {
  const { error } = await supabase
    .from("users")
    .upsert({ id: userId }, { onConflict: "id" });
  if (error) throw error;
}

/**
 * Free-tier Magic Cutout trial allowance. Free accounts get this many
 * BiRefNet cutouts before they need to subscribe. Enforced server-side
 * so reinstalling the app can't reset the counter.
 */
export const FREE_CUTOUTS_ALLOWANCE = 2;

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
 * Lifetime free-tier import allowance. The 5-portrait library cap is now
 * enforced as "5 imports ever", not "5 portraits at a time" — deleting a
 * portrait no longer frees a slot. Mirrored client-side in
 * `FreeTier.maxPortraits`.
 */
export const FREE_IMPORTS_ALLOWANCE = 5;

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
