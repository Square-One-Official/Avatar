import type { VercelRequest, VercelResponse } from "@vercel/node";
import { checkRateLimit, requireUser } from "../../lib/auth.js";
import {
  currentCredits,
  ensureUser,
  logCredit,
} from "../../lib/supabase.js";
import { prepareOutpaintInputs } from "../../lib/image.js";
import { magicCutout, outpaintBody } from "../../lib/replicate.js";

export const config = {
  api: {
    bodyParser: { sizeLimit: "15mb" },
  },
};

/**
 * POST /v1/fill-body
 *
 * Body:    { image: <base64 PNG with alpha — the current cutout>,
 *            pad_bottom_px?: number,
 *            pad_sides_px?: number }
 * Returns: 200 { cutout: <base64 PNG with alpha — extended cutout>,
 *                credits_remaining: int,
 *                pad_left: int, pad_top: int }
 *          402 { error: "insufficient_credits", credits_remaining: 0 }
 *          401 { error: "unauthorized" }
 *          429 { error: "rate_limited" }
 *
 * Reconstructs missing shoulders/torso/sides on a cropped portrait. Costs
 * 1 credit per call — no free trial (unlike Magic Cutout). Dev-allowlisted
 * users skip the credit gate so the developer can iterate.
 *
 * The client should pass `pad_bottom_px` / `pad_sides_px` matching its
 * current scale & framing so generated body content lands inside the
 * visible canvas. Server clamps both values to a sensible floor + cap
 * (see `prepareOutpaintInputs`); omitting either falls back to a default
 * ratio of the source dimensions.
 *
 * Pipeline (single user-visible operation, two Replicate calls internally):
 *   1. Pad the cutout (white below + sides), build a mask.
 *   2. Flux Fill Pro fills the masked region with photorealistic body.
 *   3. BiRefNet re-extracts a clean alpha matte from the result so the
 *      client receives a transparent-PNG cutout (same shape as /v1/cutout).
 *      We absorb the BiRefNet cost; the user pays one credit.
 *
 * Errors before deduction don't charge. Errors during either Replicate
 * call don't charge either — credit is only logged after we have the
 * final bytes in hand.
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

    if (!isDevUser) {
      const credits = await currentCredits(user.id);
      if (credits < 1) {
        res.status(402).json({ error: "insufficient_credits", credits_remaining: 0 });
        return;
      }
    }

    // 1. Pad + mask, then Flux Fill Pro. Pad sizes are caller-driven so
    //    generated body content lands inside the user's visible canvas at
    //    their preserved scale; defaults + caps in `prepareOutpaintInputs`
    //    handle missing or oversize values.
    const padBottomPxRaw = req.body?.pad_bottom_px;
    const padSidesPxRaw = req.body?.pad_sides_px;
    const padBottomPx =
      typeof padBottomPxRaw === "number" && Number.isFinite(padBottomPxRaw) && padBottomPxRaw >= 0
        ? padBottomPxRaw : undefined;
    const padSidesPx =
      typeof padSidesPxRaw === "number" && Number.isFinite(padSidesPxRaw) && padSidesPxRaw >= 0
        ? padSidesPxRaw : undefined;
    const inputs = await prepareOutpaintInputs(inputBytes, { padBottomPx, padSidesPx });
    const filledUrl = await outpaintBody({
      imageDataUrl: inputs.imageDataUrl,
      maskDataUrl: inputs.maskDataUrl,
    });

    const filledDownload = await fetch(filledUrl);
    if (!filledDownload.ok) {
      throw new Error(`Flux result fetch failed: ${filledDownload.status}`);
    }
    const filledBytes = Buffer.from(await filledDownload.arrayBuffer());
    const filledDataUrl = `data:image/png;base64,${filledBytes.toString("base64")}`;

    // 2. Re-extract alpha so the client receives a transparent cutout.
    //    BiRefNet handles the previously-white padding cleanly because the
    //    fill pipeline replaced white with photographic body content.
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

    const creditsRemaining =
      isDevUser ? 999 : await currentCredits(user.id);
    res.status(200).json({
      cutout: cutoutBytes.toString("base64"),
      credits_remaining: creditsRemaining,
      // Padding the server applied to the original cutout, in source-pixel
      // space. The client uses these to shift `offsetX/Y` deterministically
      // so the user's manual head position is preserved without depending
      // on Vision re-detecting the same eye coordinates in the new image.
      pad_left: inputs.padLeft,
      pad_top: inputs.padTop,
    });
  } catch (err) {
    console.error("/v1/fill-body error", err);
    res.status(500).json({ error: "fill_body_failed" });
  }
}
