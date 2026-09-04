import type { VercelRequest, VercelResponse } from "@vercel/node";
import { requireUser } from "../../../lib/auth.js";
import { proOverrideFor } from "../../../lib/proAccess.js";
import { activeSubscription, supabase } from "../../../lib/supabase.js";
import { fetchPublishedAnnouncements, meetsMinVersion, withinMaxVersion } from "../../../lib/payload.js";

/**
 * GET /v1/announcements/pending
 *
 * Returns the highest-priority announcement the signed-in user hasn't yet
 * dismissed, after applying audience, version, and expiry filters. The
 * macOS app calls this on sign-in and shows the result in a sheet.
 *
 * Response:
 *   { announcement: { slug, title, body, imageUrl, cta, frequency } | null }
 *
 * Headers:
 *   - Authorization: Bearer <token>   required
 *   - X-App-Version: 1.1.4            optional, used for min/maxAppVersion
 *                                     filters (absent = treated as a 1.x
 *                                     install: passes max, fails min)
 *
 * The endpoint never errors loudly to the client on Payload outages —
 * announcements are non-critical and a sign-in shouldn't fail because the
 * CMS is unreachable. We log and return `null` instead.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const user = await requireUser(req, res);
  if (!user) return;

  try {
    const announcements = await fetchPublishedAnnouncements();
    if (announcements.length === 0) {
      res.status(200).json({ announcement: null });
      return;
    }

    const appVersion = headerString(req.headers["x-app-version"]);
    const now = new Date();

    // Determine subscription state once for audience filtering.
    const sub = await activeSubscription(user.id);
    // Comped/dev accounts (E14.9) count as Pro for audience targeting.
    const isPro =
      (sub !== null && (sub.status === "active" || sub.status === "trialing")) ||
      (await proOverrideFor(user.email)) !== null;

    // Pull every "seen" slug for this user in a single round-trip rather
    // than per-announcement.
    const { data: seenRows } = await supabase
      .from("announcement_seen")
      .select("slug")
      .eq("user_id", user.id);
    const seenSlugs = new Set((seenRows ?? []).map((r) => (r as { slug: string }).slug));

    for (const a of announcements) {
      // Expired (untilDate or expiresAt in the past) → skip.
      if (a.expiresAt && new Date(a.expiresAt) < now) continue;
      if (a.frequency === "untilDate" && a.untilDate && new Date(a.untilDate) < now) continue;

      // Audience filter.
      if (a.audience === "freeUsers" && isPro) continue;
      if (a.audience === "proUsers" && !isPro) continue;
      if (a.audience === "specificEmails") {
        const email = (user.email ?? "").toLowerCase();
        if (!a.audienceEmails.includes(email)) continue;
      }

      // App-version gates (min for "needs feature X", max for "1.x only",
      // e.g. the Aaavatar 2 launch notice).
      if (!meetsMinVersion(appVersion, a.minAppVersion)) continue;
      if (!withinMaxVersion(appVersion, a.maxAppVersion)) continue;

      // Already dismissed → only `everySignInUntilDismissed` would re-show,
      // and even that respects the dismissed action; once a slug is seen we
      // stop showing it. To re-show, the publisher creates a new slug.
      if (seenSlugs.has(a.slug)) continue;

      res.status(200).json({
        announcement: {
          slug: a.slug,
          title: a.title,
          body: a.body,
          image_url: a.imageUrl,
          cta: a.cta,
          frequency: a.frequency,
        },
      });
      return;
    }

    res.status(200).json({ announcement: null });
  } catch (err) {
    console.error("/v1/announcements/pending error", err);
    // Soft-fail: never block the client over a CMS issue.
    res.status(200).json({ announcement: null });
  }
}

function headerString(v: string | string[] | undefined): string | null {
  if (typeof v === "string") return v;
  if (Array.isArray(v) && v.length > 0) return v[0];
  return null;
}
