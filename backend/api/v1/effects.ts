import type { VercelRequest, VercelResponse } from "@vercel/node";
import { CMS_LIST_CACHE_CONTROL, fetchActiveEffects, thumbnailVariant } from "../../lib/payload.js";

/**
 * GET /v1/effects (E33)
 *
 * The CMS-driven list of Effects styles the macOS Editor shows in its
 * Effects panel. Authored in Payload (admin.aaavatar.nl → Effects); adding a
 * row ships a new effect without an app or backend deploy. Each item carries
 * the style `key` (sent back to /v1/stylize), a display `label`, an optional
 * `thumbnail_url`, and a sort `order`.
 *
 * The generation `prompt` is intentionally NOT exposed — it stays server-side
 * (only /v1/stylize reads it) so users can't lift it or run free-form prompts
 * on our Replicate account.
 *
 * Anonymous-friendly (the list is non-secret), like /v1/badges. Soft-fails to
 * an empty list so a CMS hiccup degrades to the client's built-in fallback
 * effects rather than a 5xx.
 *
 * Response: { effects: [ { key, label, thumbnail_url, order } ] }
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  try {
    const effects = await fetchActiveEffects();
    res.setHeader("Cache-Control", CMS_LIST_CACHE_CONTROL);
    res.status(200).json({
      effects: effects.map((e) => ({
        key: e.key,
        label: e.label,
        // E52.1: verkleinde variant voor de 112×152 pt stijl-kaart (@2x → 320 px).
        thumbnail_url: thumbnailVariant(e.thumbnailUrl, 320),
        order: e.order,
      })),
    });
  } catch (err) {
    console.error("/v1/effects error", err instanceof Error ? err.message : String(err));
    res.status(200).json({ effects: [] });
  }
}
