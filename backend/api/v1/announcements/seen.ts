import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireUser } from "../../../lib/auth.js";
import { supabase } from "../../../lib/supabase.js";

/**
 * POST /v1/announcements/seen
 *
 * Marks an announcement as seen by the calling user. Idempotent on
 * (user_id, slug) — repeated calls are no-ops, which lets the client fire
 * this from both the dismiss tap and `.onDisappear` without duplicating
 * rows.
 *
 * Body: { slug: string, action: "dismissed" | "cta_clicked" }
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const user = await requireUser(req, res);
  if (!user) return;

  const body = (req.body ?? {}) as { slug?: unknown; action?: unknown };
  const slug = typeof body.slug === "string" ? body.slug.trim() : "";
  const action = body.action === "cta_clicked" ? "cta_clicked" : "dismissed";

  if (!slug) {
    res.status(400).json({ error: "slug required" });
    return;
  }

  try {
    const { error } = await supabase
      .from("announcement_seen")
      .upsert(
        { user_id: user.id, slug, action, seen_at: new Date().toISOString() },
        { onConflict: "user_id,slug" },
      );
    if (error) throw error;

    res.status(200).json({ ok: true });
  } catch (err) {
    console.error("/v1/announcements/seen error", err);
    res.status(500).json({ error: "Internal error" });
  }
}
