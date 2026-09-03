import type { VercelRequest, VercelResponse } from "@vercel/node";
import { checkRateLimit, requireUser } from "../../lib/auth.js";
import { MODEL_REGISTRY, resolveModelOverride, UnknownModelOverrideError } from "../../lib/models.js";
import { proOverrideFor } from "../../lib/proAccess.js";
import {
  currentCredits,
  ensureCompedCredits,
  ensureUser,
  logCredit,
} from "../../lib/supabase.js";
import { flattenOnGrey, reapplyAlpha } from "../../lib/image.js";
import { resolveImageInput } from "../../lib/uploads.js";
import { colorize, ReplicateTimeoutError } from "../../lib/replicate.js";

export const config = {
  api: {
    bodyParser: { sizeLimit: "15mb" },
  },
};

/**
 * POST /v1/colorize
 *
 * Body:    { image?: <base64 PNG with alpha>,        // legacy inline
 *            storage_key?: "<userId>/<uuid>.png" }   // upload-bypass (groot beeld)
 * Returns: 200 success
 *            { cutout: <base64 PNG>, credits_remaining: int }
 *          402 insufficient_credits
 *          401 unauthorized
 *          429 rate_limited
 *
 * Pipeline:
 *   1. Flatten cutout RGBA over neutral grey so DeOldify (RGB-only) gets
 *      a normal photo to colorize. Alpha is preserved separately for the
 *      re-attach step.
 *   2. Check credits (402 if empty).
 *   3. Run DeOldify on the flattened RGB.
 *   4. Re-attach the original alpha channel onto the colorized RGB so the
 *      client receives a transparent cutout consistent with /v1/cutout.
 *   5. Log 1 credit, return the new cutout.
 *
 * Errors before the credit-deducting Replicate call don't charge.
 *
 * Geometry is preserved end-to-end (same dimensions in/out, same
 * silhouette), so unlike /v1/fill-body the client doesn't need to
 * re-detect face/body or re-align the canvas.
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

  // Input: inline base64 (legacy) of een Storage-upload (storage_key,
  // omzeilt de 4.5 MB body-cap).
  const inputBytes = await resolveImageInput(req, res, user.id);
  if (!inputBytes) return;

  // E14.9 — the Pro list: CMS `pro-access` first, DEV_UNLIMITED_EMAILS as
  // break-glass. "unlimited" skips credit accounting entirely; a comped Pro
  // gets this month's allowance and then spends credits like anyone else.
  const override = await proOverrideFor(user.email);
  const isDevUser = override?.mode === "unlimited";
  if (override?.mode === "pro") {
    await ensureCompedCredits(user.id, override.monthlyCredits);
  }

  // E01.10: optional model override — dev-only, whitelist in MODEL_REGISTRY.
  let modelRef: string | null;
  try {
    modelRef = resolveModelOverride("colorize", req.body?.model_override, isDevUser);
  } catch (e) {
    if (e instanceof UnknownModelOverrideError) {
      res.status(400).json({ error: "unknown_model_override" });
      return;
    }
    throw e;
  }

  try {
    await ensureUser(user.id);

    // Step 1: flatten over grey so DeOldify gets RGB it can work with.
    // Pure server-side image work — safe to do before the credit gate.
    const flattened = await flattenOnGrey(inputBytes);
    const flattenedDataUrl = `data:image/png;base64,${flattened.toString("base64")}`;

    // Step 2: credit gate. Only checked once we know we're going to do
    // billable work.
    if (!isDevUser) {
      const credits = await currentCredits(user.id);
      if (credits < MODEL_REGISTRY.colorize.credits) {
        res.status(402).json({ error: "insufficient_credits", credits_remaining: 0 });
        return;
      }
    }

    // Step 3: DeOldify colorizes the RGB.
    const colorizedUrl = await colorize({ imageDataUrl: flattenedDataUrl, model: modelRef });
    const colorizedDownload = await fetch(colorizedUrl);
    if (!colorizedDownload.ok) {
      throw new Error(`DeOldify result fetch failed: ${colorizedDownload.status}`);
    }
    const colorizedBytes = Buffer.from(await colorizedDownload.arrayBuffer());

    // Step 4: re-attach the original alpha so the client gets a
    // transparent cutout, not an RGB rectangle on grey.
    const cutoutBytes = await reapplyAlpha(colorizedBytes, inputBytes);

    if (!isDevUser) {
      await logCredit({
        userId: user.id,
        delta: -MODEL_REGISTRY.colorize.credits,
        reason: "colorize",
        ref: colorizedUrl,
      });
    }

    const creditsRemaining = isDevUser ? 999 : await currentCredits(user.id);
    res.status(200).json({
      cutout: cutoutBytes.toString("base64"),
      credits_remaining: creditsRemaining,
    });
  } catch (err) {
    // Log the message only — the Replicate SDK embeds the auth header in the
    // full error object, so logging `err` whole leaks REPLICATE_API_TOKEN.
    const msg = err instanceof Error ? err.message : String(err);
    console.error("/v1/colorize error:", msg);
    if (err instanceof ReplicateTimeoutError) {
      res.status(504).json({ error: "model_timeout" });
      return;
    }
    // Replicate rate-limits (low balance, burst exceeded) bubble up as
    // 429s. Propagate so the client surfaces the friendly throttle copy
    // instead of "colorize_failed".
    if (
      msg.includes("status 429") ||
      msg.includes("Too Many Requests") ||
      msg.toLowerCase().includes("throttled")
    ) {
      res.status(429).json({ error: "rate_limited" });
      return;
    }
    res.status(500).json({ error: "colorize_failed" });
  }
}
