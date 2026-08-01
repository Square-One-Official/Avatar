import type { VercelRequest, VercelResponse } from "@vercel/node";
import { checkRateLimit, requireUser } from "../../lib/auth.js";
import { proOverrideFor } from "../../lib/proAccess.js";
import { activeSubscription, ensureUser } from "../../lib/supabase.js";
import { resolveImageInput } from "../../lib/uploads.js";
import {
  createCustomEffect,
  customEffectThumbnailUrl,
  listCustomEffects,
} from "../../lib/customEffects.js";

export const config = {
  api: {
    bodyParser: { sizeLimit: "8mb" },
  },
};

/**
 * /v1/custom-effects (E34) — a Pro user's own Effects.
 *
 * GET  -> { effects: [ { id, label, thumbnail_url, order } ] }
 *        The list the Effects panel renders under "Your effects". The
 *        generation prompt (the user's description) is NOT exposed, mirroring
 *        /v1/effects -- it stays server-side (only /v1/stylize reads it).
 *
 * POST -> create one. Body:
 *          { storage_key: "<userId>/<uuid>.png",   // reference image (upload-bypass)
 *            description?: <string <=300>,          // style refinement; optional
 *            label?: <string <=40> }                // optional, else derived
 *        Returns 201 { effect: { id, label, thumbnail_url, order } }.
 *        The reference PNG was uploaded straight to the cutout-uploads bucket
 *        via /v1/cutout/upload-url; here we read it (resolveImageInput) and
 *        re-store it in the public custom-effects bucket as the persistent
 *        reference + thumbnail.
 *
 * Both paths are Pro-only (403 pro_required) -- custom effects are a Pro
 * capability. Applying one (and being charged a credit) happens in /v1/stylize.
 */
const MAX_DESCRIPTION = 300;
const MAX_LABEL = 40;

// Control characters (incl. newlines/tabs) and DEL -> collapsed to a space so
// the description can't smuggle prompt-structure into the model call.
const CONTROL_CHARS = /[\x00-\x1F\x7F]+/g;

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const user = await requireUser(req, res);
  if (!user) return;

  // Pro gate -- the create/list capability is Pro-only. Dev-allowlisted users
  // pass too (they skip every gate, E01.10).
  const isPro =
    (await proOverrideFor(user.email)) !== null || (await activeSubscription(user.id)) !== null;
  if (!isPro) {
    res.status(403).json({ error: "pro_required" });
    return;
  }

  if (req.method === "GET") {
    try {
      const rows = await listCustomEffects(user.id);
      res.status(200).json({
        effects: rows.map((row, i) => ({
          id: row.id,
          label: row.label,
          thumbnail_url: customEffectThumbnailUrl(row.reference_path),
          order: i,
        })),
      });
    } catch (err) {
      console.error("/v1/custom-effects GET error", err instanceof Error ? err.message : String(err));
      res.status(500).json({ error: "list_failed" });
    }
    return;
  }

  if (req.method === "POST") {
    if (!(await checkRateLimit(user.id))) {
      res.status(429).json({ error: "rate_limited" });
      return;
    }

    // Description (the style refinement) -- optional; the reference image
    // carries the style. Strip control chars and cap length.
    const rawDescription = (req.body?.description ?? "") as string;
    if (typeof rawDescription !== "string" || rawDescription.length > MAX_DESCRIPTION * 4) {
      res.status(400).json({ error: "invalid_description" });
      return;
    }
    const description = rawDescription.replace(CONTROL_CHARS, " ").trim().slice(0, MAX_DESCRIPTION);
    // NOTE(E34): basic guard only (length + control-char strip). A dedicated
    // text/image moderation pass (e.g. an OpenAI moderation call on the
    // description and a vision check on the reference) is the follow-up before
    // this is opened beyond beta -- the description becomes a model prompt on
    // our Replicate account.

    const rawLabel = (req.body?.label ?? "") as string;
    const label = deriveLabel(typeof rawLabel === "string" ? rawLabel : "", description);

    // Reference image: read the upload-bypass object (downloads + deletes it
    // from cutout-uploads). Validates the key namespace + size.
    const referenceBytes = await resolveImageInput(req, res, user.id);
    if (!referenceBytes) return;

    try {
      await ensureUser(user.id);
      const row = await createCustomEffect({
        userId: user.id,
        label,
        prompt: description,
        referenceBytes,
      });
      res.status(201).json({
        effect: {
          id: row.id,
          label: row.label,
          thumbnail_url: customEffectThumbnailUrl(row.reference_path),
          order: 0,
        },
      });
    } catch (err) {
      console.error("/v1/custom-effects POST error", err instanceof Error ? err.message : String(err));
      res.status(500).json({ error: "create_failed" });
    }
    return;
  }

  res.status(405).json({ error: "method_not_allowed" });
}

/**
 * A short card label. Prefer an explicit label; else derive from the first
 * words of the description; else a neutral default.
 */
function deriveLabel(rawLabel: string, description: string): string {
  const explicit = rawLabel.replace(CONTROL_CHARS, " ").trim().slice(0, MAX_LABEL);
  if (explicit) return explicit;
  const fromDesc = description.split(/\s+/).slice(0, 4).join(" ").slice(0, MAX_LABEL).trim();
  return fromDesc || "Custom effect";
}
