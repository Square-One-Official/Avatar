import type { VercelRequest, VercelResponse } from "@vercel/node";
import { checkRateLimit, requireUser } from "../../lib/auth.js";
import {
  currentCredits,
  ensureUser,
  logCredit,
} from "../../lib/supabase.js";
import { padForOutpaint } from "../../lib/image.js";
import { magicCutout, outpaintPortrait } from "../../lib/replicate.js";

export const config = {
  api: {
    bodyParser: { sizeLimit: "15mb" },
  },
};

/**
 * POST /v1/fill-body
 *
 * Body:    { image: <base64 PNG with alpha — the current cutout> }
 * Returns: 200 success
 *            { cutout: <base64 PNG>, credits_remaining: int }
 *          402 insufficient_credits
 *          401 unauthorized
 *          429 rate_limited
 *
 * Pipeline (real outpainting, not instruction-edit):
 *   1. Build outpaint inputs from the cutout PNG: a padded grey canvas
 *      with the person composited on top, plus a white-on-fill mask.
 *      The original RGBA pixels are preserved bit-for-bit, so identity
 *      can't drift.
 *   2. Check credits (402 if empty).
 *   3. Run FLUX.1 Fill Pro on (image, mask). It only paints into the
 *      masked region.
 *   4. Re-extract alpha via BiRefNet (`magicCutout`) so the client gets
 *      a transparent cutout consistent with `/v1/cutout`'s output shape.
 *   5. Log 1 credit, return the new cutout.
 *
 * Errors before the credit-deducting Replicate call don't charge.
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

  const base64 = (req.body?.image ?? "") as string;
  if (!base64 || typeof base64 !== "string") {
    res.status(400).json({ error: "missing_image" });
    return;
  }

  const cleaned = base64.replace(/^data:image\/[a-z]+;base64,/i, "");
  let inputBytes: Buffer;
  try {
    inputBytes = Buffer.from(cleaned, "base64");
  } catch {
    res.status(400).json({ error: "invalid_base64" });
    return;
  }
  if (inputBytes.length === 0 || inputBytes.length > 12 * 1024 * 1024) {
    res.status(400).json({ error: "image_size_out_of_range" });
    return;
  }

  const devEmails = (process.env.DEV_UNLIMITED_EMAILS ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  const isDevUser = !!user.email && devEmails.includes(user.email.toLowerCase());

  try {
    await ensureUser(user.id);

    // Step 1: build the outpaint inputs. Pure server-side image work,
    // no Replicate calls — safe to do before the credit gate.
    const { padded, mask } = await padForOutpaint(inputBytes);
    const paddedDataUrl = `data:image/png;base64,${padded.toString("base64")}`;
    const maskDataUrl = `data:image/png;base64,${mask.toString("base64")}`;

    // Step 2: credit gate. Only checked once we know we're going to do
    // billable work.
    if (!isDevUser) {
      const credits = await currentCredits(user.id);
      if (credits < 1) {
        res.status(402).json({ error: "insufficient_credits", credits_remaining: 0 });
        return;
      }
    }

    // Step 3: FLUX Fill Pro paints into the masked margin only.
    const filledUrl = await outpaintPortrait({
      imageDataUrl: paddedDataUrl,
      maskDataUrl,
    });
    const filledDownload = await fetch(filledUrl);
    if (!filledDownload.ok) {
      throw new Error(`Flux Fill result fetch failed: ${filledDownload.status}`);
    }
    const filledBytes = Buffer.from(await filledDownload.arrayBuffer());
    const filledDataUrl = `data:image/png;base64,${filledBytes.toString("base64")}`;

    // Step 4: BiRefNet to re-extract alpha so the client receives a
    // transparent cutout consistent with /v1/cutout's shape.
    const cutoutUrl = await magicCutout({ imageDataUrl: filledDataUrl });
    const cutoutDownload = await fetch(cutoutUrl);
    if (!cutoutDownload.ok) {
      throw new Error(`BiRefNet result fetch failed: ${cutoutDownload.status}`);
    }
    const cutoutBytes = Buffer.from(await cutoutDownload.arrayBuffer());

    if (!isDevUser) {
      await logCredit({
        userId: user.id,
        delta: -1,
        reason: "fill_body",
        ref: filledUrl,
      });
    }

    const creditsRemaining = isDevUser ? 999 : await currentCredits(user.id);
    res.status(200).json({
      cutout: cutoutBytes.toString("base64"),
      credits_remaining: creditsRemaining,
    });
  } catch (err) {
    console.error("/v1/fill-body error", err);
    // Replicate rate-limits (low balance, burst exceeded, etc.) bubble up
    // as 429s. Propagate them so the client's existing rateLimited handler
    // surfaces "Too many requests. Please wait a moment." instead of the
    // catch-all 500 — much friendlier than "fill_body_failed" in a toast.
    const msg = err instanceof Error ? err.message : String(err);
    if (
      msg.includes("status 429") ||
      msg.includes("Too Many Requests") ||
      msg.toLowerCase().includes("throttled")
    ) {
      res.status(429).json({ error: "rate_limited" });
      return;
    }
    res.status(500).json({ error: "fill_body_failed" });
  }
}
