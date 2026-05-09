import type { VercelRequest, VercelResponse } from "@vercel/node";
import { optionalUser } from "../../lib/auth.js";
import { supabase } from "../../lib/supabase.js";
import { fetchPublishedAnnouncements } from "../../lib/payload.js";

/**
 * GET /v1/badges
 *
 * Returns the active "NEW" badges the macOS app should overlay on
 * registered components. Each badge is tied to an announcement: the badge
 * lives for `durationDays` after the announcement was published, and
 * disappears once the user has dismissed the announcement (so signing in
 * + acknowledging the pop-up clears the matching badges).
 *
 * Anonymous-friendly: if no Bearer token is sent, badges still render
 * (their content is non-secret) but seen-state isn't applied — the user
 * gets a slightly "loud" pre-sign-in experience that resolves on sign-in.
 *
 * Response:
 *   { badges: [ { component_id: string, expires_at: iso8601 } ] }
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const userResult = await optionalUser(req, res);
  if (userResult === "rejected") return;

  try {
    const announcements = await fetchPublishedAnnouncements();
    const now = Date.now();

    let seenSlugs = new Set<string>();
    if (userResult) {
      const { data: rows } = await supabase
        .from("announcement_seen")
        .select("slug")
        .eq("user_id", userResult.id);
      seenSlugs = new Set((rows ?? []).map((r) => (r as { slug: string }).slug));
    }

    // For each (componentId, announcement) keep the latest expiry. If two
    // different announcements badge the same component, the longer-living
    // one wins.
    const byComponent = new Map<string, number>();
    for (const a of announcements) {
      if (seenSlugs.has(a.slug)) continue;
      if (!a.publishedAt) continue;
      const publishedMs = new Date(a.publishedAt).getTime();
      if (Number.isNaN(publishedMs)) continue;

      for (const target of a.badgeTargets) {
        const expiresMs = publishedMs + target.durationDays * 24 * 60 * 60 * 1000;
        if (expiresMs <= now) continue;
        const prev = byComponent.get(target.componentId) ?? 0;
        if (expiresMs > prev) byComponent.set(target.componentId, expiresMs);
      }
    }

    const badges = Array.from(byComponent.entries()).map(([componentId, expiresMs]) => ({
      component_id: componentId,
      expires_at: new Date(expiresMs).toISOString(),
    }));

    res.status(200).json({ badges });
  } catch (err) {
    console.error("/v1/badges error", err);
    // Soft-fail to empty so a CMS hiccup doesn't paint stale badges.
    res.status(200).json({ badges: [] });
  }
}
