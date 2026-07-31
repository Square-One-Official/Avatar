import type { VercelRequest, VercelResponse } from "@vercel/node";
import { CMS_LIST_CACHE_CONTROL, fetchActiveHairPresets, thumbnailVariant } from "../../lib/payload.js";

/**
 * GET /v1/hair-presets — CMS-gestuurde kapsel-presets (E33+).
 *
 * Anoniem: geen auth vereist (labels zijn niet-gevoelig; prompts worden
 * NIET meegestuurd — die blijven server-side in `/v1/stylize`).
 *
 * Soft-fail: als de CMS onbereikbaar is, geeft dit endpoint `{ presets: [] }`
 * terug zodat het iOS-paneel zijn eigen hardgecodeerde fallback toont.
 *
 * Response: { presets: [{ key, label, thumbnail_url, order }] }
 * Cache:   60s in-process (zie fetchActiveHairPresets) + CDN-cache via
 *          CMS_LIST_CACHE_CONTROL (E52.1).
 */
export default async function handler(_req: VercelRequest, res: VercelResponse) {
  if (_req.method !== "GET") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  try {
    const presets = await fetchActiveHairPresets();
    res.setHeader("Cache-Control", CMS_LIST_CACHE_CONTROL);
    res.status(200).json({
      // E52.1: optionele CMS-thumbnail als verkleinde variant; null als de
      // collectie (nog) geen thumbnail-veld/waarde heeft.
      presets: presets.map(({ key, label, thumbnailUrl, order }) => ({
        key,
        label,
        thumbnail_url: thumbnailVariant(thumbnailUrl, 320),
        order,
      })),
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("/v1/hair-presets error:", msg);
    res.status(200).json({ presets: [] });
  }
}
