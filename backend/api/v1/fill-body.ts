import type { VercelRequest, VercelResponse } from "@vercel/node";
import { checkRateLimit, requireUser } from "../../lib/auth.js";
import {
  currentCredits,
  ensureUser,
  logCredit,
} from "../../lib/supabase.js";
import { flattenOnGrey } from "../../lib/image.js";
import { analyzePortrait, editPortrait, magicCutout } from "../../lib/replicate.js";

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
 *            { cutout: <base64 PNG>, credits_remaining: int, no_changes: false }
 *          200 no-op (portrait was already complete — no credit charged)
 *            { cutout: null, credits_remaining: int, no_changes: true,
 *              reason: <short text from the analyser> }
 *          402 insufficient_credits (only on the success path)
 *          401 unauthorized
 *          429 rate_limited
 *
 * Pipeline:
 *   1. Flatten alpha → grey so the analyser sees a clean silhouette.
 *   2. Gemini 2.5 Flash decides whether the portrait is already complete or
 *      what specific body parts are clipped. Always runs (cheap, ~$0.001).
 *   3. If complete → respond { no_changes: true } and return without
 *      charging a credit. Client shows "already complete" toast.
 *   4. Otherwise → check credits (402 if empty), then Flux Kontext Pro
 *      with a prompt naming the specific clipped parts, BiRefNet to
 *      re-extract alpha, log 1 credit, return new cutout.
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

    // Step 1 + 2: flatten + analyse. Always runs, regardless of credit
    // balance, so we can no-op on already-complete portraits without
    // refusing the user a free check.
    const flattened = await flattenOnGrey(inputBytes);
    const flattenedDataUrl = `data:image/png;base64,${flattened.toString("base64")}`;
    const analysis = await analyzePortrait({ imageDataUrl: flattenedDataUrl });

    if (analysis.complete) {
      const creditsRemaining = isDevUser ? 999 : await currentCredits(user.id);
      res.status(200).json({
        cutout: null,
        credits_remaining: creditsRemaining,
        no_changes: true,
        reason: "portrait_already_complete",
      });
      return;
    }

    // Step 3: credit gate. Only checked once we know we're going to do
    // billable work.
    if (!isDevUser) {
      const credits = await currentCredits(user.id);
      if (credits < 1) {
        res.status(402).json({ error: "insufficient_credits", credits_remaining: 0 });
        return;
      }
    }

    // Step 4: Flux Kontext Pro with a prompt that names the SPECIFIC
    // clipped parts Gemini identified.
    const reframedUrl = await editPortrait({
      imageDataUrl: flattenedDataUrl,
      missing: analysis.missing,
    });
    const reframedDownload = await fetch(reframedUrl);
    if (!reframedDownload.ok) {
      throw new Error(`Kontext result fetch failed: ${reframedDownload.status}`);
    }
    const reframedBytes = Buffer.from(await reframedDownload.arrayBuffer());
    const reframedDataUrl = `data:image/png;base64,${reframedBytes.toString("base64")}`;

    // Step 5: BiRefNet to re-extract alpha so the client receives a
    // transparent cutout consistent with /v1/cutout's shape.
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

    const creditsRemaining = isDevUser ? 999 : await currentCredits(user.id);
    res.status(200).json({
      cutout: cutoutBytes.toString("base64"),
      credits_remaining: creditsRemaining,
      no_changes: false,
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
