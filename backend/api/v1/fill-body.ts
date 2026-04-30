import type { VercelRequest, VercelResponse } from "@vercel/node";
import { checkRateLimit, requireUser } from "../../lib/auth.js";
import {
  currentCredits,
  ensureUser,
  logCredit,
} from "../../lib/supabase.js";
import { flattenOnGrey } from "../../lib/image.js";
import { editPortrait, magicCutout } from "../../lib/replicate.js";

export const config = {
  api: {
    bodyParser: { sizeLimit: "15mb" },
  },
};

/**
 * POST /v1/fill-body
 *
 * Body:    { image: <base64 PNG with alpha — the current cutout> }
 * Returns: 200 { cutout: <base64 PNG with alpha — extended cutout>,
 *                credits_remaining: int }
 *          402 { error: "insufficient_credits", credits_remaining: 0 }
 *          401 { error: "unauthorized" }
 *          429 { error: "rate_limited" }
 *
 * Reconstructs the person's full upper body on a cropped portrait. Costs
 * 1 credit per call — no free trial (unlike Magic Cutout). Dev-allowlisted
 * users skip the credit gate so the developer can iterate.
 *
 * Pipeline (single user-visible operation, two Replicate calls internally):
 *   1. Flatten the alpha cutout onto neutral grey so Nano Banana gets a
 *      normal RGB photo to reframe.
 *   2. Nano Banana regenerates the portrait with the full upper body
 *      visible while preserving face / hair / clothing identity.
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

    // 1. Flatten alpha → grey so Nano Banana sees a normal RGB studio photo.
    const flattened = await flattenOnGrey(inputBytes);
    const flattenedDataUrl = `data:image/png;base64,${flattened.toString("base64")}`;

    // 2. Nano Banana — instruction-based reframe with identity preservation.
    const reframedUrl = await editPortrait({ imageDataUrl: flattenedDataUrl });
    const reframedDownload = await fetch(reframedUrl);
    if (!reframedDownload.ok) {
      throw new Error(`Nano Banana result fetch failed: ${reframedDownload.status}`);
    }
    const reframedBytes = Buffer.from(await reframedDownload.arrayBuffer());
    const reframedDataUrl = `data:image/png;base64,${reframedBytes.toString("base64")}`;

    // 3. Re-extract alpha so the client receives a transparent cutout
    //    consistent with /v1/cutout's shape.
    const cutoutUrl = await magicCutout({ imageDataUrl: reframedDataUrl });
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
        ref: reframedUrl,
      });
    }

    const creditsRemaining =
      isDevUser ? 999 : await currentCredits(user.id);
    res.status(200).json({
      cutout: cutoutBytes.toString("base64"),
      credits_remaining: creditsRemaining,
    });
  } catch (err) {
    console.error("/v1/fill-body error", err);
    res.status(500).json({ error: "fill_body_failed" });
  }
}
