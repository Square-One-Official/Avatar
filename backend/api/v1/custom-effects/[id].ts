import type { VercelRequest, VercelResponse } from "@vercel/node";
import { isDevUnlimitedUser, requireUser } from "../../../lib/auth.js";
import { activeSubscription } from "../../../lib/supabase.js";
import { deleteCustomEffect } from "../../../lib/customEffects.js";

/**
 * DELETE /v1/custom-effects/:id (E34) — remove one of the caller's own custom
 * effects (row + reference object). Pro-only, owner-scoped.
 *
 * Returns 200 { ok: true } · 404 not_found · 403 pro_required.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "DELETE") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const user = await requireUser(req, res);
  if (!user) return;

  const isPro =
    isDevUnlimitedUser(user.email) || (await activeSubscription(user.id)) !== null;
  if (!isPro) {
    res.status(403).json({ error: "pro_required" });
    return;
  }

  const rawId = req.query.id;
  const id = Array.isArray(rawId) ? rawId[0] : rawId;
  if (!id || typeof id !== "string") {
    res.status(400).json({ error: "missing_id" });
    return;
  }

  try {
    const ok = await deleteCustomEffect(user.id, id);
    if (!ok) {
      res.status(404).json({ error: "not_found" });
      return;
    }
    res.status(200).json({ ok: true });
  } catch (err) {
    console.error("/v1/custom-effects/[id] DELETE error", err instanceof Error ? err.message : String(err));
    res.status(500).json({ error: "delete_failed" });
  }
}
