import type { VercelRequest, VercelResponse } from "@vercel/node";
import { randomUUID } from "node:crypto";
import { checkRateLimit, requireUser } from "../../../lib/auth.js";
import { supabase } from "../../../lib/supabase.js";

/**
 * POST /v1/cutout/upload-url
 *
 * Issues a short-lived signed PUT URL into the private `cutout-uploads`
 * bucket so the iOS client can upload a Magic Cutout input PNG directly to
 * Supabase Storage, bypassing Vercel's 4.5 MB serverless body cap. The
 * client follows up with `POST /v1/cutout { storage_key }` once the upload
 * lands.
 *
 * The returned `key` is namespaced by user id (`{userId}/{uuid}.png`) so a
 * compromised client can't trample on another user's prefix — `/v1/cutout`
 * later verifies the key starts with the caller's user id before signing a
 * read URL.
 *
 * Returns:
 *   200 { url, key, expires_in }
 *   401 { error: "unauthorized" }
 *   429 { error: "rate_limited" }
 *   500 { error: "sign_failed" }
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const user = await requireUser(req, res);
  if (!user) return;
  if (!(await checkRateLimit(user.id))) {
    res.status(429).json({ error: "rate_limited" });
    return;
  }

  const key = `${user.id}/${randomUUID()}.png`;

  try {
    const { data, error } = await supabase.storage
      .from("cutout-uploads")
      .createSignedUploadUrl(key);
    if (error || !data?.signedUrl) {
      console.error("/v1/cutout/upload-url sign error", error);
      res.status(500).json({ error: "sign_failed" });
      return;
    }
    // Supabase signed upload URLs are single-use and expire after 2h by
    // default; we surface a conservative TTL to the client so it knows to
    // refresh if it stalls between getting the URL and uploading.
    res.status(200).json({
      url: data.signedUrl,
      key,
      expires_in: 60,
    });
  } catch (err) {
    console.error("/v1/cutout/upload-url error", err);
    res.status(500).json({ error: "sign_failed" });
  }
}
