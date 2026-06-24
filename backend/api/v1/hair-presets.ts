import type { VercelRequest, VercelResponse } from "@vercel/node";
import { fetchActiveHairPresets } from "../../lib/payload.js";

/**
 * GET /v1/hair-presets — CMS-gestuurde kapsel-presets (E33+).
 *
 * Anoniem: geen auth vereist (labels zijn niet-gevoelig; prompts worden
 * NIET meegestuurd — die blijven server-side in `/v1/stylize`).
 *
 * Soft-fail: als de CMS onbereikbaar is, geeft dit endpoint `{ presets: [] }`
 * terug zodat het iOS-paneel zijn eigen hardgecodeerde fallback toont.
 *
 * Response: { presets: [{ key, label, order }] }
 * Cache:   60s in-process (zie fetchActiveHairPresets); client mag zelf
 *          nog eens 60s cachen (Cache-Control: max-age=60).
 */
export default async function handler(_req: VercelRequest, res: VercelResponse) {
  if (_req.method !== "GET") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  try {
    const presets = await fetchActiveHairPresets();
    res.setHeader("Cache-Control", "public, max-age=60, stale-while-revalidate=120");
    res.status(200).json({
      presets: presets.map(({ key, label, order }) => ({ key, label, order })),
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("/v1/hair-presets error:", msg);
    res.status(200).json({ presets: [] });
  }
}
