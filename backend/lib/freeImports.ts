/**
 * E14.11 — free-import counters as the client should see them.
 *
 * `/v1/import-claim` (try_consume_free_import) denies when EITHER the
 * account counter (`users.free_imports_used`) or the device counter
 * (`device_imports.free_imports_used`) is at the allowance. `/v1/account`
 * must therefore report the effective counter, max(user, device), or the
 * app renders "3 left of 3 images" right next to a denied import and the
 * E14.10 pre-flight thinks a drop still fits.
 *
 * Pure (no Supabase import) so it is unit-testable without env.
 */
export type FreeImportCounters = {
  free_imports_used: number;
  free_imports_remaining: number;
};

export function freeImportCounters(
  userUsed: number | null | undefined,
  deviceUsed: number | null | undefined,
  allowance: number,
): FreeImportCounters {
  const user = typeof userUsed === "number" && userUsed > 0 ? userUsed : 0;
  const device = typeof deviceUsed === "number" && deviceUsed > 0 ? deviceUsed : 0;
  const used = Math.min(allowance, Math.max(user, device));
  return {
    free_imports_used: used,
    free_imports_remaining: Math.max(0, allowance - used),
  };
}
