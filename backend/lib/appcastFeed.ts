import type { VercelRequest, VercelResponse } from "@vercel/node";
import { readFile } from "node:fs/promises";

/**
 * Shared Sparkle-feed handler for `/appcast.xml` (v1) and `/appcast-v2.xml`
 * (Aaavatar 2). Caching, ETag and 304 behaviour stay identical so the two
 * channels cannot drift.
 */

function djb2(s: string): number {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return h >>> 0;
}

export function makeAppcastHandler(filePath: string) {
  let cached: { body: string; etag: string } | null = null;

  async function load(): Promise<{ body: string; etag: string }> {
    if (cached) return cached;
    const body = await readFile(filePath, "utf8");
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
      console.error("appcast handler error", err);
      res.status(500).send("appcast unavailable");
    }
  };
}
