import type { VercelRequest, VercelResponse } from "@vercel/node";
import { CMS_LIST_CACHE_CONTROL, fetchActiveFacePresets, thumbnailVariant } from "../../lib/payload.js";

/**
 * GET /v1/face-presets — CMS-gestuurde face beauty-presets (E33+).
 *
 * Anoniem: geen auth vereist (labels zijn niet-gevoelig; prompts worden
 * NIET meegestuurd — die blijven server-side in `/v1/stylize`).
 *
 * Soft-fail: als de CMS onbereikbaar is, geeft dit endpoint `{ presets: [] }`
 * terug zodat het iOS-paneel zijn eigen hardgecodeerde fallback toont.
 *
 * Response: { presets: [{ key, label, thumbnail_url, order }] }
 */
export default async function handler(_req: VercelRequest, res: VercelResponse) {
  if (_req.method !== "GET") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  try {
    const presets = await fetchActiveFacePresets();
    res.setHeader("Cache-Control", CMS_LIST_CACHE_CONTROL);
    res.status(200).json({
      // E52.1: optionele CMS-thumbnail als verkleinde variant (null zonder veld).
      presets: presets.map(({ key, label, thumbnailUrl, order }) => ({
        key,
        label,
        thumbnail_url: thumbnailVariant(thumbnailUrl, 320),
        order,
      })),
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("/v1/face-presets error:", msg);
    res.status(200).json({ presets: [] });
  }
}
