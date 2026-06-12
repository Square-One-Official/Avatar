import type { VercelRequest, VercelResponse } from "@vercel/node";
import sharp from "sharp";
import { checkRateLimit, isDevUnlimitedUser, requireUser } from "../../lib/auth.js";
import { resolveModelOverride, UnknownModelOverrideError } from "../../lib/models.js";
import { ensureUser } from "../../lib/supabase.js";
import { flattenOnGrey, MAX_DECODED_IMAGE_BYTES } from "../../lib/image.js";
import { ReplicateTimeoutError, stylizeEdit } from "../../lib/replicate.js";

export const config = {
  api: {
    bodyParser: { sizeLimit: "15mb" },
  },
};

/**
 * POST /v1/stylize — DEV-ONLY (E09.1 bakeoff-mechanisme).
 *
 * Body:    { image: <base64 PNG — cutout of vlak portret>,
 *            prompt: <instructie, ≤2000 tekens>,
 *            model_override?: <whitelist-key uit MODEL_REGISTRY.stylize> }
 * Returns: 200 { image: <base64 PNG>, model: <gebruikte key/ref> }
 *          403 dev_only — geen publiek endpoint
 *
 * Bewust gegated op de DEV_UNLIMITED_EMAILS-allowlist: een vrij prompt-veld
 * op andermans Replicate-rekening is geen API-oppervlak. E09.2 vervangt de
 * vrije prompt door een server-side stijl→prompt-mapping en haalt deze gate
 * weg; tot die tijd is er ook geen credit-aftrek (dev-users betalen nooit).
 *
 * Pipeline: flatten op grijs (modellen interpreteren alpha onvoorspelbaar,
 * zelfde reden als colorize) → instruction-edit via stylizeEdit →
 * resultaat-PNG terug. Geen alpha-herextractie: de bakeoff beoordeelt het
 * ruwe modelresultaat; productie-plumbing (cutout-herextractie zoals
 * fill-body stap 4) is een E09.2-zorg.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const user = await requireUser(req, res);
  if (!user) return;

  if (!isDevUnlimitedUser(user.email)) {
    res.status(403).json({ error: "dev_only" });
    return;
  }

  if (!(await checkRateLimit(user.id))) {
    res.status(429).json({ error: "rate_limited" });
    return;
  }

  const base64 = (req.body?.image ?? "") as string;
  if (!base64 || typeof base64 !== "string") {
    res.status(400).json({ error: "missing_image" });
    return;
  }
  const prompt = (req.body?.prompt ?? "") as string;
  if (!prompt || typeof prompt !== "string" || prompt.length > 2000) {
    res.status(400).json({ error: "missing_or_oversized_prompt" });
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

  let modelRef: string | null;
  try {
    modelRef = resolveModelOverride("stylize", req.body?.model_override, true);
  } catch (e) {
    if (e instanceof UnknownModelOverrideError) {
      res.status(400).json({ error: "unknown_model_override" });
      return;
    }
    throw e;
  }

  try {
    await ensureUser(user.id);

    const flattened = await flattenOnGrey(inputBytes);
    const meta = await sharp(flattened).metadata();
    const flatDataUrl = `data:image/png;base64,${flattened.toString("base64")}`;

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

    res.status(200).json({
      image: resultBytes.toString("base64"),
      model: modelRef ?? "default",
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
