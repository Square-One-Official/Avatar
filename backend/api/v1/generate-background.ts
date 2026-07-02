import type { VercelRequest, VercelResponse } from "@vercel/node";
import sharp from "sharp";
import { checkRateLimit, isDevUnlimitedUser, requireUser } from "../../lib/auth.js";
import {
  MODEL_REGISTRY,
  resolveGenerationModel,
  resolveModelOverride,
  UnknownModelOverrideError,
} from "../../lib/models.js";
import { currentCredits, ensureUser, logCredit } from "../../lib/supabase.js";
import { generateBackgroundImage, ReplicateTimeoutError } from "../../lib/replicate.js";
import { uploadResultImage } from "../../lib/uploads.js";

export const config = {
  api: {
    bodyParser: { sizeLimit: "1mb" },
  },
};

const BACKGROUND_CLAUSE =
  "Empty seamless background scene, no people, no faces, no text, no logos, no watermark.";

const STYLE_SUFFIX: Record<string, string> = {
  photorealistic: "photorealistic, natural lighting",
  illustration: "digital illustration, clean lines",
  line: "line art, minimal shading",
  bold: "bold graphic style, strong contrast",
  watercolour: "watercolour painting",
  pencil: "pencil sketch",
  "3d": "3D rendered, soft studio lighting",
};

const VIEW_SUFFIX: Record<string, string> = {
  "45_angle": "45 degree angle view",
  high_angle: "high angle view",
  low_angle: "low angle view",
  overhead: "overhead view",
  close_up: "close-up view",
  wide: "wide view",
  front: "front view",
  side: "side view",
  back: "back view",
};

function backgroundCreditCost(width: number, height: number): number {
  const ratio = width / Math.max(height, 1);
  return ratio >= 2.5 ? 3 : MODEL_REGISTRY.generate_background.credits;
}

function buildBackgroundPrompt(
  userPrompt: string,
  styleKey: string,
  customStyleText: string | undefined,
  viewKey: string,
): string | null {
  const trimmed = userPrompt.trim();
  if (!trimmed || trimmed.length > 500) return null;

  let stylePart: string;
  if (styleKey === "custom") {
    const custom = (customStyleText ?? "").trim();
    if (!custom || custom.length > 120) return null;
    stylePart = custom;
  } else {
    stylePart = STYLE_SUFFIX[styleKey];
    if (!stylePart) return null;
  }

  const viewPart = viewKey !== "any" ? VIEW_SUFFIX[viewKey] : undefined;
  const parts = [
    `Create a full-frame background image: ${trimmed}.`,
    stylePart,
    viewPart,
    BACKGROUND_CLAUSE,
  ].filter(Boolean);
  return parts.join(" ");
}

function clampDimension(value: unknown, fallback: number): number {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(64, Math.min(2048, Math.round(n)));
}

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

  const userPrompt = req.body?.user_prompt;
  const styleKey = req.body?.style_key;
  const viewKey = req.body?.view_key ?? "any";
  const customStyleText = req.body?.custom_style_text;
  const targetWidth = clampDimension(req.body?.target_width, 1024);
  const targetHeight = clampDimension(req.body?.target_height, 1024);

  if (typeof userPrompt !== "string" || typeof styleKey !== "string" || typeof viewKey !== "string") {
    res.status(400).json({ error: "invalid_request" });
    return;
  }

  const prompt = buildBackgroundPrompt(userPrompt, styleKey, customStyleText, viewKey);
  if (!prompt) {
    res.status(400).json({ error: "invalid_prompt" });
    return;
  }

  const isDevUser = isDevUnlimitedUser(user.email);
  const creditCost = backgroundCreditCost(targetWidth, targetHeight);

  let modelRef: string | null;
  try {
    modelRef = resolveModelOverride("generate_background", req.body?.model_override, isDevUser);
  } catch (e) {
    if (e instanceof UnknownModelOverrideError) {
      res.status(400).json({ error: "unknown_model_override" });
      return;
    }
    throw e;
  }
  if (!modelRef) {
    modelRef = resolveGenerationModel("generate_background", req.body?.generation_model);
  }

  try {
    await ensureUser(user.id);

    let preChargeCredits = 0;
    if (!isDevUser) {
      preChargeCredits = await currentCredits(user.id);
      if (preChargeCredits < creditCost) {
        res.status(402).json({ error: "insufficient_credits", credits_remaining: preChargeCredits });
        return;
      }
    }

    const canvas = await sharp({
      create: {
        width: targetWidth,
        height: targetHeight,
        channels: 3,
        background: { r: 200, g: 200, b: 205 },
      },
    })
      .png()
      .toBuffer();
    const canvasDataUrl = `data:image/png;base64,${canvas.toString("base64")}`;

    const resultUrl = await generateBackgroundImage({
      prompt,
      imageDataUrl: canvasDataUrl,
      width: targetWidth,
      height: targetHeight,
      model: modelRef,
    });

    const download = await fetch(resultUrl);
    if (!download.ok) {
      throw new Error(`generate-background result fetch failed: ${download.status}`);
    }
    const original = Buffer.from(await download.arrayBuffer());

    // WebP (lossy q90) keeps a full-frame, opaque background well under the
    // size at which inline base64 would blow Vercel's ~4.5 MB response cap.
    // sharp().toBuffer() already returns a Buffer — no re-wrap needed.
    const resultBytes = await sharp(original)
      .resize(targetWidth, targetHeight, { fit: "cover", position: "centre" })
      .webp({ quality: 90 })
      .toBuffer();

    // Deliver via a signed Storage URL, never inline base64: a full-frame
    // background as base64 can exceed Vercel's ~4.5 MB response body cap and
    // truncate silently (charged credit, no image). Upload + sign BEFORE
    // charging so a delivery failure can never bill the user — a throw here
    // flows to the catch → 500, with no credit logged.
    const { url: imageUrl, key: resultKey } = await uploadResultImage(
      user.id,
      resultBytes,
      "webp",
    );

    if (!isDevUser) {
      await logCredit({
        userId: user.id,
        delta: -creditCost,
        reason: "generate_background",
        // Stable correlation id for the ledger row: the key encodes the user
        // + a unique id and stays meaningful even after the sweep cron removes
        // the object (~1h) — unlike the opaque, expiring Replicate URL (~24h).
        ref: resultKey,
      });
    }

    // The credit is spent and the image is uploaded — reading the fresh
    // balance must never turn a delivered generation into a 500
    // (charged-but-no-image). Fall back to the locally-derived balance; the
    // client refreshes separately and ignores this value anyway.
    let creditsRemaining = isDevUser ? 999 : preChargeCredits - creditCost;
    if (!isDevUser) {
      try {
        creditsRemaining = await currentCredits(user.id);
      } catch (e) {
        console.warn("/v1/generate-background post-charge credits read failed:", e);
      }
    }
    res.status(200).json({
      image_url: imageUrl,
      credits_remaining: creditsRemaining,
      model: modelRef ?? MODEL_REGISTRY.generate_background.defaultModel,
      target_width: targetWidth,
      target_height: targetHeight,
      credits_charged: creditCost,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("/v1/generate-background error:", msg);
    if (err instanceof ReplicateTimeoutError) {
      res.status(504).json({ error: "model_timeout" });
      return;
    }
    if (
      msg.includes("status 429") ||
      msg.includes("Too Many Requests") ||
      msg.toLowerCase().includes("throttled")
    ) {
      res.status(429).json({ error: "rate_limited" });
      return;
    }
    if (msg.toLowerCase().includes("moderation") || msg.toLowerCase().includes("safety")) {
      res.status(400).json({ error: "content_policy" });
      return;
    }
    res.status(500).json({ error: "generate_background_failed" });
  }
}
