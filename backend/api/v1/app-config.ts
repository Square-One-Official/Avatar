import type { VercelRequest, VercelResponse } from "@vercel/node";
import { fetchAppConfig } from "../../lib/payload.js";

/**
 * GET /v1/app-config (E33+)
 *
 * App-brede visuele configuratie vanuit de CMS (Payload Global "App configuration").
 * Anoniem-vriendelijk — gebruikt tijdens Onboarding vóórdat de gebruiker is ingelogd.
 * Soft-fail: bij een CMS-probleem keert het de lege fallback-staat terug zodat de
 * hardgecodeerde placeholders in de app zichtbaar blijven.
 *
 * Response: {
 *   splash_background_url: string | null,     ← Onboarding Splash achtergrond
 *   empty_state_avatar_urls: string[]          ← Lege-canvas-cirkels (max 6)
 * }
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  try {
    const config = await fetchAppConfig();
    res.status(200).json({
      splash_background_url: config.splashBackgroundUrl,
      empty_state_avatar_urls: config.emptyStateAvatarUrls,
    });
  } catch (err) {
    console.error("/v1/app-config error", err instanceof Error ? err.message : String(err));
    res.status(200).json({ splash_background_url: null, empty_state_avatar_urls: [] });
  }
}
