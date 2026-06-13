import type { VercelRequest, VercelResponse } from "@vercel/node";
import sharp from "sharp";
import { checkRateLimit, isDevUnlimitedUser, requireUser } from "../../lib/auth.js";
import {
  MODEL_REGISTRY,
  resolveModelOverride,
  UnknownModelOverrideError,
} from "../../lib/models.js";
import { currentCredits, ensureUser, logCredit } from "../../lib/supabase.js";
import { flattenOnGrey, MAX_DECODED_IMAGE_BYTES } from "../../lib/image.js";
import { ReplicateTimeoutError, stylizeEdit } from "../../lib/replicate.js";

export const config = {
  api: {
    bodyParser: { sizeLimit: "15mb" },
  },
};

/**
 * Server-side stijl→prompt-mapping (E09.2). De vier stijlen + de gedeelde
 * identity-clausule komen 1-op-1 uit de E09.1-bakeoff (nano-banana behield
 * daar de identiteit het best; de clausule is dragend voor die score —
 * niet aanpassen zonder nieuwe bakeoff). Productie-gebruikers kiezen ALLEEN
 * uit deze keys; een vrij prompt-veld op andermans Replicate-rekening blijft
 * dev-only (zie hieronder).
 */
const IDENTITY_CLAUSE =
  "Keep the person's facial features, expression, hairstyle and clothing clearly recognizable so the person remains identifiable.";

const STYLE_PROMPTS: Record<string, string> = {
  clay:
    "Transform this portrait into a claymation-style clay sculpture character: smooth modelling-clay skin with subtle hand-sculpted texture, soft studio lighting. " +
    IDENTITY_CLAUSE,
  wood:
    "Transform this portrait into a hand-carved wooden figurine: visible wood grain, warm natural wood tones, slightly stylized carving. " +
    IDENTITY_CLAUSE,
  "3d":
    "Transform this portrait into a stylized 3D animated-film character render: soft skin shading, subtle subsurface scattering, gentle exaggeration of features. " +
    IDENTITY_CLAUSE,
  scribble:
    "Transform this portrait into a loose hand-drawn scribble illustration: expressive sketchy ink lines, minimal flat colour accents, plain light background. " +
    IDENTITY_CLAUSE,
};

/**
 * POST /v1/stylize — Effects (E09.2; productie sinds de promotie van het
 * dev-only E09.1-bakeoff-endpoint).
 *
 * Body:    { image: <base64 PNG — cutout of vlak portret>,
 *            style?: "clay" | "wood" | "3d" | "scribble",   // productieroute
 *            prompt?: <vrije instructie ≤2000 tekens>,       // ALLEEN dev
 *            model_override?: <whitelist-key uit MODEL_REGISTRY.stylize> }   // ALLEEN dev
 * Returns: 200 { image: <base64 PNG>, credits_remaining: int, model: <key> }
 *          400 unknown_style / missing_or_oversized_prompt / missing_image
 *          402 insufficient_credits
 *          429 rate_limited · 504 model_timeout
 *
 * Pipeline (zoals colorize, met credit-gate): flatten op grijs (modellen
 * interpreteren alpha onvoorspelbaar) → instruction-edit via stylizeEdit →
 * resultaat-PNG terug. Geen alpha-herextractie: een Effects-render is een
 * nieuw, vol portret dat de kaart vult — een her-cutout zou een extra
 * cutout-call kosten zonder visuele winst (E09.2-besluit).
 *
 * Credit-gate identiek aan colorize.ts: alleen niet-dev-users betalen,
 * gecheckt ná het server-side voorwerk en vóór de billable Replicate-call;
 * fouten vóór die call rekenen nooit af.
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

  const isDevUser = isDevUnlimitedUser(user.email);

  // Prompt-bepaling: productie kiest een `style` (server-side mapping); een
  // vrij `prompt` is alléén voor dev-users (bakeoff/handmatig testen).
  let prompt: string;
  const styleKey = (req.body?.style ?? "") as string;
  const freePrompt = (req.body?.prompt ?? "") as string;
  if (styleKey) {
    const mapped = STYLE_PROMPTS[styleKey];
    if (!mapped) {
      res.status(400).json({ error: "unknown_style" });
      return;
    }
    prompt = mapped;
  } else if (freePrompt && isDevUser) {
    if (typeof freePrompt !== "string" || freePrompt.length > 2000) {
      res.status(400).json({ error: "missing_or_oversized_prompt" });
      return;
    }
    prompt = freePrompt;
  } else {
    // Niet-dev zonder geldige `style`, of dev zonder style én zonder prompt.
    res.status(400).json({ error: "unknown_style" });
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
  if (inputBytes.length === 0 || inputBytes.length > MAX_DECODED_IMAGE_BYTES) {
    res.status(400).json({ error: "image_size_out_of_range" });
    return;
  }

  // E01.10: optionele model-override — dev-only, whitelist in MODEL_REGISTRY.
  let modelRef: string | null;
  try {
    modelRef = resolveModelOverride("stylize", req.body?.model_override, isDevUser);
  } catch (e) {
    if (e instanceof UnknownModelOverrideError) {
      res.status(400).json({ error: "unknown_model_override" });
      return;
    }
    throw e;
  }

  try {
    await ensureUser(user.id);

    // Server-side voorwerk vóór de credit-gate: flatten op grijs.
    const flattened = await flattenOnGrey(inputBytes);
    const meta = await sharp(flattened).metadata();
    const flatDataUrl = `data:image/png;base64,${flattened.toString("base64")}`;

    // Credit-gate (alleen niet-dev), net als colorize.
    if (!isDevUser) {
      const credits = await currentCredits(user.id);
      if (credits < MODEL_REGISTRY.stylize.credits) {
        res.status(402).json({ error: "insufficient_credits", credits_remaining: 0 });
        return;
      }
    }

    const resultUrl = await stylizeEdit({
      imageDataUrl: flatDataUrl,
      prompt,
      width: meta.width ?? 0,
      height: meta.height ?? 0,
      model: modelRef,
    });
    const download = await fetch(resultUrl);
    if (!download.ok) {
      throw new Error(`stylize result fetch failed: ${download.status}`);
    }
    const resultBytes = Buffer.from(await download.arrayBuffer());

    if (!isDevUser) {
      await logCredit({
        userId: user.id,
        delta: -MODEL_REGISTRY.stylize.credits,
        reason: "stylize",
        ref: resultUrl,
      });
    }

    const creditsRemaining = isDevUser ? 999 : await currentCredits(user.id);
    res.status(200).json({
      image: resultBytes.toString("base64"),
      credits_remaining: creditsRemaining,
      model: modelRef ?? MODEL_REGISTRY.stylize.defaultModel,
    });
  } catch (err) {
    console.error("/v1/stylize error", err);
    if (err instanceof ReplicateTimeoutError) {
      res.status(504).json({ error: "model_timeout" });
      return;
    }
    const msg = err instanceof Error ? err.message : String(err);
    if (
      msg.includes("status 429") ||
      msg.includes("Too Many Requests") ||
      msg.toLowerCase().includes("throttled")
    ) {
      res.status(429).json({ error: "rate_limited" });
      return;
    }
    res.status(500).json({ error: "stylize_failed" });
  }
}
