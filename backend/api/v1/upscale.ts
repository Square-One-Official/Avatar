import type { VercelRequest, VercelResponse } from "@vercel/node";
import { checkRateLimit, isDevUnlimitedUser, requireUser } from "../../lib/auth.js";
import { MODEL_REGISTRY, resolveModelOverride, UnknownModelOverrideError } from "../../lib/models.js";
import { currentCredits, ensureUser, logCredit } from "../../lib/supabase.js";
import { flattenOnGrey, reapplyAlpha } from "../../lib/image.js";
import { resolveImageInput } from "../../lib/uploads.js";
import { ReplicateTimeoutError, upscale } from "../../lib/replicate.js";

export const config = {
  api: {
    bodyParser: { sizeLimit: "15mb" },
  },
};

/**
 * POST /v1/upscale — "Boost resolution" (E10.3).
 *
 * Body:    { image?: <base64 PNG with alpha>,        // legacy inline
 *            storage_key?: "<userId>/<uuid>.png" }   // upload-bypass (groot beeld)
 * Returns: 200 { cutout: <base64 PNG>, credits_remaining: int }
 *          402 insufficient_credits · 401 · 429 · 504
 *
 * Pipeline (zoals colorize, met credit-gate):
 *   1. Flatten de cutout op grijs — Real-ESRGAN negeert alpha.
 *   2. Credit-gate (402 als leeg; alleen niet-dev betaalt).
 *   3. Real-ESRGAN 2× upscale op de RGB.
 *   4. Hang het oorspronkelijke alfa er weer aan, herschaald naar de nieuwe
 *      maat (reapplyAlpha) — resultaat blijft een transparante cutout.
 *   5. Log 1 credit, geef de grotere cutout terug.
 *
 * Fouten vóór de billable Replicate-call rekenen nooit af.
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

  const isDevUser = isDevUnlimitedUser(user.email);

  // E01.10: optionele model-override — dev-only, whitelist in MODEL_REGISTRY.
  let modelRef: string | null;
  try {
    modelRef = resolveModelOverride("upscale", req.body?.model_override, isDevUser);
  } catch (e) {
    if (e instanceof UnknownModelOverrideError) {
      res.status(400).json({ error: "unknown_model_override" });
      return;
    }
    throw e;
  }

  try {
    await ensureUser(user.id);

    // Step 1: flatten op grijs (Real-ESRGAN negeert alpha). Pure server-side
    // beeldbewerking — veilig vóór de credit-gate.
    const flattened = await flattenOnGrey(inputBytes);
    const flattenedDataUrl = `data:image/png;base64,${flattened.toString("base64")}`;

    // Step 2: credit-gate (alleen niet-dev).
    if (!isDevUser) {
      const credits = await currentCredits(user.id);
      if (credits < MODEL_REGISTRY.upscale.credits) {
        res.status(402).json({ error: "insufficient_credits", credits_remaining: 0 });
        return;
      }
    }

    // Step 3: Real-ESRGAN upscale.
    const upscaledUrl = await upscale({ imageDataUrl: flattenedDataUrl, model: modelRef });
    const download = await fetch(upscaledUrl);
    if (!download.ok) {
      throw new Error(`upscale result fetch failed: ${download.status}`);
    }
    const upscaledBytes = Buffer.from(await download.arrayBuffer());

    // Step 4: alfa weer aanhangen (herschaald naar de nieuwe maat).
    const cutoutBytes = await reapplyAlpha(upscaledBytes, inputBytes);

    if (!isDevUser) {
      await logCredit({
        userId: user.id,
        delta: -MODEL_REGISTRY.upscale.credits,
        reason: "upscale",
        ref: upscaledUrl,
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
    console.error("/v1/upscale error:", msg);
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
    res.status(500).json({ error: "upscale_failed" });
  }
}
