import type { VercelRequest, VercelResponse } from "@vercel/node";
import { fetchFeatureFlags } from "../../lib/payload.js";

/**
 * GET /v1/feature-flags — Remote feature flags (E33+).
 *
 * Anoniem: geen auth vereist (vlaggen zijn niet-gevoelig). De iOS-app haalt
 * deze flags op bij startup om toolbar-knoppen in/uit te schakelen.
 *
 * Soft-fail: als de CMS onbereikbaar is, worden alle flags `true` teruggegeven
 * (veilige standaard: functies aan). Zo breekt de app nooit bij een CMS-storing.
 *
 * Response:
 *   { effects_enabled, hair_enabled, clothes_enabled, face_enabled, backgrounds_enabled }
 */
export default async function handler(_req: VercelRequest, res: VercelResponse) {
  if (_req.method !== "GET") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  try {
    const flags = await fetchFeatureFlags();
    res.setHeader("Cache-Control", "public, max-age=60, stale-while-revalidate=120");
    res.status(200).json({
      effects_enabled: flags.effectsEnabled,
      hair_enabled: flags.hairEnabled,
      clothes_enabled: flags.clothesEnabled,
      face_enabled: flags.faceEnabled,
      backgrounds_enabled: flags.backgroundsEnabled,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("/v1/feature-flags error:", msg);
    res.status(200).json({
      effects_enabled: true,
      hair_enabled: true,
      clothes_enabled: true,
      face_enabled: true,
      backgrounds_enabled: true,
    });
  }
}
