import type { VercelRequest, VercelResponse } from "@vercel/node";
import { fetchActiveBackgrounds } from "../../lib/payload.js";

/**
 * GET /v1/backgrounds (E33+)
 *
 * CMS-driven list of background images shown in the macOS Editor's Background
 * panel. Each item has a stable `key`, a display `label`, a `category` string
 * used to group items into panel sections, a full-res `image_url` for export
 * compositing, and an optional `thumbnail_url` for the panel swatch.
 *
 * Authored in Payload (admin.aaavatar.nl → Backgrounds). Adding a row ships a
 * new background without an app or backend deploy.
 *
 * Anonymous-friendly (no auth required). Soft-fails to { backgrounds: [] } on
 * error so a CMS hiccup degrades to the app's built-in gradient/color presets.
 *
 * Response: { backgrounds: [{ key, label, category, image_url, thumbnail_url, order }] }
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  try {
    const backgrounds = await fetchActiveBackgrounds();
    res.status(200).json({
      backgrounds: backgrounds.map((b) => ({
        key: b.key,
        label: b.label,
        category: b.category,
        image_url: b.imageUrl,
        thumbnail_url: b.thumbnailUrl ?? b.imageUrl,
        order: b.order,
      })),
    });
  } catch (err) {
    console.error("/v1/backgrounds error", err instanceof Error ? err.message : String(err));
    res.status(200).json({ backgrounds: [] });
  }
}
