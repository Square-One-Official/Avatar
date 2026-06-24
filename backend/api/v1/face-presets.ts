import type { VercelRequest, VercelResponse } from "@vercel/node";
import { fetchActiveFacePresets } from "../../lib/payload.js";

/**
 * GET /v1/face-presets — CMS-gestuurde face beauty-presets (E33+).
 *
 * Anoniem: geen auth vereist (labels zijn niet-gevoelig; prompts worden
 * NIET meegestuurd — die blijven server-side in `/v1/stylize`).
 *
 * Soft-fail: als de CMS onbereikbaar is, geeft dit endpoint `{ presets: [] }`
 * terug zodat het iOS-paneel zijn eigen hardgecodeerde fallback toont.
 *
 * Response: { presets: [{ key, label, order }] }
 */
export default async function handler(_req: VercelRequest, res: VercelResponse) {
  if (_req.method !== "GET") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  try {
    const presets = await fetchActiveFacePresets();
    res.setHeader("Cache-Control", "public, max-age=60, stale-while-revalidate=120");
    res.status(200).json({
      presets: presets.map(({ key, label, order }) => ({ key, label, order })),
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("/v1/face-presets error:", msg);
    res.status(200).json({ presets: [] });
  }
}
