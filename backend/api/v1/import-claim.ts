import type { VercelRequest, VercelResponse } from "@vercel/node";
import { optionalUser, requireDeviceFingerprint } from "../../lib/auth.js";
import {
  activeSubscription,
  ensureUser,
  FREE_IMPORTS_ALLOWANCE,
  tryConsumeFreeImport,
} from "../../lib/supabase.js";

/**
 * POST /v1/import-claim
 *
 * Header:  X-Device-Fingerprint: <UUID>   (required, even when anonymous)
 *          Authorization: Bearer <token>  (optional)
 * Body:    (empty)
 * Returns: 200 { allowed: true,  imports_used: int, imports_remaining: int }
 *          402 { allowed: false, imports_used: int, imports_remaining: 0 }
 *          400 { error: "missing_device_fingerprint" }
 *          401 { error: "..." }   // only when an explicit, invalid token is sent
 *
 * Atomically reserves one lifetime free-import slot before the client
 * runs an import (Subject Lift OR Magic Cutout). Three layers of cap,
 * any one of which can deny:
 *   1. Account counter (`users.free_imports_used`)        — sign-in identity
 *   2. Device counter  (`device_imports.free_imports_used`) — Keychain UUID
 *   3. (Pro short-circuit: signed-in Pro users always allowed; no
 *      counter is touched.)
 *
 * Anonymous callers (no Authorization header) are gated only by the
 * device counter — signing in later still hits the device cap, so
 * burning the trial signed-out doesn't grant a fresh allowance.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const fp = requireDeviceFingerprint(req, res);
  if (!fp) return; // 400 already written

  const user = await optionalUser(req, res);
  if (user === "rejected") return; // 401 already written

  try {
    if (user) {
      await ensureUser(user.id);
      // Pro users skip the gate entirely. We still report a sentinel
      // counter pair so the client can render "unlimited" without a
      // separate code path.
      const sub = await activeSubscription(user.id);
      if (sub) {
        res.status(200).json({
          allowed: true,
          imports_used: 0,
          imports_remaining: FREE_IMPORTS_ALLOWANCE,
          pro: true,
        });
        return;
      }
    }

    const result = await tryConsumeFreeImport(user?.id ?? null, fp);
    const used = Math.max(result.userUsed, result.deviceUsed);
    const remaining = Math.max(0, result.allowance - used);

    if (!result.allowed) {
      res.status(402).json({
        allowed: false,
        imports_used: used,
        imports_remaining: 0,
      });
      return;
    }

    res.status(200).json({
      allowed: true,
      imports_used: used,
      imports_remaining: remaining,
    });
  } catch (err) {
    console.error("/v1/import-claim error", err);
    res.status(500).json({ error: "claim_failed" });
  }
}
