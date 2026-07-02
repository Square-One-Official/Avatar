import { timingSafeEqual } from "node:crypto";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "../../lib/supabase.js";
import { RESULT_BUCKET } from "../../lib/uploads.js";

/**
 * GET /api/cron/sweep-generated-results
 *
 * Vercel-cron endpoint. Deletes stale objects from the `generated-results`
 * bucket. Unlike the input bucket (`cutout-uploads`), result objects can't be
 * deleted inline: /v1/generate-background hands the client a signed URL and the
 * client downloads it asynchronously, so the server never learns when the
 * object is done. The signed URL expires after 10 minutes and the client
 * fetches within seconds, so anything older than `MAX_AGE_MS` is certainly
 * consumed and safe to drop. Without this sweep the bucket would grow without
 * bound (one WebP per generation, forever).
 *
 * Layout is `<userId>/<uuid>.webp`, so we walk one folder level deep. Each
 * folder is gathered fully before deleting (offset-based pagination would skip
 * entries if we deleted mid-walk). The run is time-boxed; if it can't finish,
 * it returns `partial: true` and the next hourly run continues — stale objects
 * stay eligible until removed.
 *
 * Auth: protected by CRON_SECRET via the Authorization header (Vercel sets this
 *       automatically for cron requests; manual hits must include
 *       `Authorization: Bearer <CRON_SECRET>`).
 */
const MAX_AGE_MS = 60 * 60 * 1000; // 1 hour
const PAGE = 1000;
const TIME_BUDGET_MS = 50_000; // leave headroom under the 60s maxDuration

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const expected = process.env.CRON_SECRET;
  if (!expected) {
    console.error("CRON_SECRET not configured");
    res.status(500).json({ error: "cron_misconfigured" });
    return;
  }
  const authHeader = req.headers.authorization;
  const auth = Array.isArray(authHeader) ? authHeader[0] : authHeader;
  if (!isAuthorized(auth, expected)) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  const startedAt = Date.now();
  const cutoff = startedAt - MAX_AGE_MS;
  let folders = 0;
  let scanned = 0;
  let deleted = 0;
  let partial = false;
  const errors: string[] = [];

  try {
    // Phase 1 — enumerate every user-folder name BEFORE deleting anything.
    // Folders are virtual: a folder vanishes from the listing the moment its
    // last object is removed. If we deleted while paginating folders, those
    // disappearances would shift the offset and skip later folders. Listing
    // all names first keeps the top-level enumeration stable. Folders surface
    // as placeholders with `id === null`.
    const topEntries = await listAll("", errors);
    const folderNames = topEntries.filter((e) => e.id === null).map((e) => e.name);

    // Phase 2 — per folder, gather its objects fully, then delete the stale
    // ones. Gathering before deleting avoids the same offset-shift inside the
    // folder.
    for (const prefix of folderNames) {
      if (Date.now() - startedAt > TIME_BUDGET_MS) {
        partial = true;
        break;
      }
      folders++;

      const objects = (await listAll(prefix, errors)).filter((e) => e.id !== null);
      scanned += objects.length;

      const stalePaths = objects
        .filter((o) => o.createdAt !== null && Date.parse(o.createdAt) < cutoff)
        .map((o) => `${prefix}/${o.name}`);

      for (let i = 0; i < stalePaths.length; i += PAGE) {
        if (Date.now() - startedAt > TIME_BUDGET_MS) {
          partial = true;
          break;
        }
        const batch = stalePaths.slice(i, i + PAGE);
        const { error: rerr } = await supabase.storage.from(RESULT_BUCKET).remove(batch);
        if (rerr) errors.push(`remove ${prefix}: ${rerr.message}`);
        else deleted += batch.length;
      }
    }

    res.status(200).json({ folders, scanned, deleted, partial, errors });
  } catch (err) {
    console.error("/api/cron/sweep-generated-results error", err);
    res.status(500).json({ error: "cron_failed", message: (err as Error).message });
  }
}

/**
 * Lists every entry under `prefix`, paginating until a page comes back empty.
 * Advancing by the ACTUAL returned count (not the requested `limit`) keeps this
 * correct even if Supabase caps a page below PAGE — a `length < PAGE` terminator
 * would stop early and leak the tail. Returns raw entries so the caller decides
 * folder (`id === null`) vs object. A list error stops this prefix and is
 * recorded; the sweep moves on (the next hourly run retries).
 */
async function listAll(
  prefix: string,
  errors: string[],
): Promise<{ name: string; id: string | null; createdAt: string | null }[]> {
  const out: { name: string; id: string | null; createdAt: string | null }[] = [];
  let offset = 0;
  for (;;) {
    const { data, error } = await supabase.storage
      .from(RESULT_BUCKET)
      .list(prefix, { limit: PAGE, offset });
    if (error) {
      errors.push(`list ${prefix || "/"}: ${error.message}`);
      break;
    }
    if (!data || data.length === 0) break;
    for (const e of data) {
      out.push({ name: e.name, id: e.id, createdAt: e.created_at ?? null });
    }
    offset += data.length;
  }
  return out;
}

/**
 * Constant-time bearer-token check (mirrors grant-yearly-credits). A plain
 * `!==` short-circuits on the first mismatched byte — a side channel for
 * brute-forcing the secret. `timingSafeEqual` needs equal-length buffers, so
 * we length-check first; the secret's length is a Vercel-config artifact, not
 * itself a secret.
 */
function isAuthorized(received: string | undefined, expected: string): boolean {
  if (typeof received !== "string") return false;
  const expectedHeader = `Bearer ${expected}`;
  if (received.length !== expectedHeader.length) return false;
  return timingSafeEqual(Buffer.from(received), Buffer.from(expectedHeader));
}
