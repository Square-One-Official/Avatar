import type { VercelRequest, VercelResponse } from "@vercel/node";
import { readFile } from "node:fs/promises";

/**
 * Gedeelde Sparkle-feed-server (E13.1). Twee kanalen delen exact dezelfde
 * mechaniek — `/appcast.xml` (v1) en `/appcast-v2.xml` (Aaavatar 2) — dus de
 * loader/cache/etag-logica leeft hier één keer en de route-bestanden zijn
 * dunne wrappers. Zie api/appcast.ts voor de trust-root-rationale
 * (self-hosted i.p.v. GitHub raw, audit HIGH #10).
 */

type Cached = { body: string; etag: string };

function djb2(s: string): number {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return h >>> 0;
}

export function makeAppcastHandler(filePath: string) {
  // Eén cache per route-module; Fluid Compute hergebruikt instanties dus de
  // disk-read is geamortiseerd.
  let cached: Cached | null = null;

  async function load(): Promise<Cached> {
    if (cached) return cached;
    const body = await readFile(filePath, "utf8");
    // Zwakke etag — content-afgeleid, deterministisch over cold starts.
    const etag = `W/"${body.length.toString(36)}-${djb2(body).toString(36)}"`;
    cached = { body, etag };
    return cached;
  }

  return async function handler(req: VercelRequest, res: VercelResponse) {
    if (req.method !== "GET" && req.method !== "HEAD") {
      res.status(405).setHeader("Allow", "GET, HEAD").end();
      return;
    }
    try {
      const { body, etag } = await load();
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
      console.error("appcast read failed:", err instanceof Error ? err.message : String(err));
      res.status(500).json({ error: "appcast_unavailable" });
    }
  };
}
