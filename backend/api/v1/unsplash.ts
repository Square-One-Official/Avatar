import type { VercelRequest, VercelResponse } from "@vercel/node";
import { checkAnonUnsplashRateLimit, clientIp, optionalUser } from "../../lib/auth.js";

/**
 * POST /v1/unsplash (UX-audit background-paneel, 2026-07-03)
 *
 * Proxy voor de Unsplash API zodat de access key nooit in de app zit
 * (Unsplash-guideline: keys server-side houden, downloads registreren).
 *
 * Body-varianten:
 *   { q?: string }    → zoekresultaten; lege/afwezige q = editorial feed.
 *   { track: string } → registreert een download via de door Unsplash
 *                       meegegeven `download_location` (verplicht op apply).
 *
 * Zonder `UNSPLASH_ACCESS_KEY` env var: { enabled: false, photos: [] } —
 * de app verbergt de Unsplash-inhoud dan met een nette melding (soft-fail,
 * zelfde patroon als /v1/backgrounds).
 *
 * Response: { enabled, photos: [{ id, thumb_url, full_url, author_name,
 *             author_url, download_location }] } of { ok: true } bij track.
 */

// Verplichte attributie-parameters op auteur-links (Unsplash-guideline).
const UTM = "utm_source=aaavatar&utm_medium=referral";

interface UnsplashApiPhoto {
  id?: string;
  urls?: { raw?: string; small?: string; regular?: string };
  user?: { name?: string; links?: { html?: string } };
  links?: { download_location?: string };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  // Anonymous is fine (the background panel works pre-sign-in), but a
  // token that is present and invalid is still a 401 — same contract as
  // /v1/account — and every caller shares a per-IP budget so one host can't
  // exhaust the Unsplash key quota for everyone (release-review 2026-09-04).
  const userResult = await optionalUser(req, res);
  if (userResult === "rejected") return; // optionalUser already wrote 401
  if (!(await checkAnonUnsplashRateLimit(clientIp(req)))) {
    res.status(429).json({ error: "rate_limited" });
    return;
  }

  const key = process.env.UNSPLASH_ACCESS_KEY;
  if (!key) {
    res.status(200).json({ enabled: false, photos: [] });
    return;
  }
  const headers = { Authorization: `Client-ID ${key}`, "Accept-Version": "v1" };

  // Download-registratie: alleen de door Unsplash zelf geleverde
  // api.unsplash.com-URL accepteren (geen open proxy).
  const track = req.body?.track;
  if (typeof track === "string") {
    if (track.startsWith("https://api.unsplash.com/")) {
      try {
        await fetch(track, { headers });
      } catch {
        // Best-effort: een gemiste registratie mag apply nooit blokkeren.
      }
    }
    res.status(200).json({ ok: true });
    return;
  }

  const q = typeof req.body?.q === "string" ? req.body.q.trim().slice(0, 100) : "";
  const url = q
    ? `https://api.unsplash.com/search/photos?per_page=24&query=${encodeURIComponent(q)}`
    : "https://api.unsplash.com/photos?per_page=24";

  try {
    const upstream = await fetch(url, { headers });
    if (!upstream.ok) throw new Error(`unsplash_${upstream.status}`);
    const json = (await upstream.json()) as UnsplashApiPhoto[] | { results?: UnsplashApiPhoto[] };
    const items = Array.isArray(json) ? json : (json.results ?? []);
    res.status(200).json({
      enabled: true,
      photos: items
        .map((p) => ({
          id: p.id,
          thumb_url: p.urls?.small,
          // Export-compositing verdient resolutie: raw + Imgix-resize naar
          // 2048 (PortraitExporter.exportSide) i.p.v. de zware originele full.
          full_url: p.urls?.raw ? `${p.urls.raw}&w=2048&fit=max&q=85` : p.urls?.regular,
          author_name: p.user?.name ?? null,
          author_url: p.user?.links?.html ? `${p.user.links.html}?${UTM}` : null,
          download_location: p.links?.download_location ?? null,
        }))
        .filter((p) => p.id && p.thumb_url && p.full_url),
    });
  } catch (err) {
    console.error("/v1/unsplash error", err instanceof Error ? err.message : String(err));
    res.status(200).json({ enabled: true, photos: [] });
  }
}
