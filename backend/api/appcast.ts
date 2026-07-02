import type { VercelRequest, VercelResponse } from "@vercel/node";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

/**
 * GET /appcast.xml  (rewritten in vercel.json → /api/appcast)
 *
 * Sparkle feed for the macOS app, served from infrastructure we control
 * (audit HIGH #10). Previously the feed lived at
 *   https://raw.githubusercontent.com/Square-One-Official/Avatar/main/appcast.xml
 * which means GitHub holds the trust root for our update channel — a
 * compromised GitHub account or a BGP-hijack of `raw.githubusercontent.com`
 * could push a malicious appcast to every install. Sparkle's per-item
 * EdDSA signature catches a tampered DMG, but the appcast itself was
 * trusted-by-host. Serving it from `api.aaavatar.nl` re-anchors the
 * trust root to the same domain that already authenticates Avatar's
 * other backend calls (now with TLS pinning — see TLSPinning.swift).
 *
 * The canonical `appcast.xml` still lives at the repo root and continues
 * to be served by GitHub raw so older builds (which have the GitHub
 * SUFeedURL baked in) keep receiving updates during the transition. New
 * builds point at api.aaavatar.nl/appcast.xml.
 *
 * Caching: 5 minutes browser + edge. The macOS app checks for updates
 * once a day; the limit matters mostly for back-to-back GitHub-Action
 * verification hits.
 */

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Read once per warm function instance. Fluid Compute reuses instances
// across invocations so the disk read is amortised; the few KB also fit
// in V8's string-intern table.
let cached: { body: string; etag: string } | null = null;

async function loadAppcast(): Promise<{ body: string; etag: string }> {
  if (cached) return cached;
  const filePath = path.join(__dirname, "_appcast.xml");
  const body = await readFile(filePath, "utf8");
  // Weak etag — content-derived, deterministic across cold starts so a
  // browser If-None-Match round-trip can short-circuit on a 304.
  const etag = `W/"${body.length.toString(36)}-${djb2(body).toString(36)}"`;
  cached = { body, etag };
  return cached;
}

function djb2(s: string): number {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return h >>> 0;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.status(405).setHeader("Allow", "GET, HEAD").end();
    return;
  }

  try {
    const { body, etag } = await loadAppcast();
    res.setHeader("Content-Type", "application/xml; charset=utf-8");
    res.setHeader("Cache-Control", "public, max-age=300, s-maxage=300");
    res.setHeader("ETag", etag);
    if (req.headers["if-none-match"] === etag) {
      res.status(304).end();
      return;
    }
    if (req.method === "HEAD") {
      res.status(200).end();
      return;
    }
    res.status(200).send(body);
  } catch (err) {
    console.error("appcast handler error", err);
    res.status(500).send("appcast unavailable");
  }
}
