import type { VercelRequest, VercelResponse } from "@vercel/node";
import { fetchActiveBannerPresets } from "../../lib/payload.js";

/**
 * GET /v1/banner-presets (E39)
 *
 * The CMS-driven list of Banner presets the macOS app shows in its Banners
 * empty-state / home. Authored in Payload (admin.aaavatar.nl → Banner Presets);
 * adding a row ships a new starting point without an app or backend deploy.
 * Picking one opens the Banner Studio prefilled. Each item carries a stable
 * `key`, a display `label`, a `category` (grouping), an optional
 * `thumbnail_url`, the layer-stack `config` (an opaque JSON string the app
 * decodes into its own BannerLayers), and a sort `order`.
 *
 * Anonymous-friendly (the list is non-secret), like /v1/effects. Soft-fails to
 * an empty list so a CMS hiccup degrades to the client's built-in fallback
 * presets rather than a 5xx.
 *
 * Response: { banner_presets: [ { key, label, category, thumbnail_url, config, order } ] }
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  try {
    const presets = await fetchActiveBannerPresets();
    res.status(200).json({
      banner_presets: presets.map((p) => ({
        key: p.key,
        label: p.label,
        category: p.category,
        thumbnail_url: p.thumbnailUrl,
        config: p.config,
        order: p.order,
      })),
    });
  } catch (err) {
    console.error("/v1/banner-presets error", err instanceof Error ? err.message : String(err));
    res.status(200).json({ banner_presets: [] });
  }
}
