import type { VercelRequest, VercelResponse } from "@vercel/node";
import { checkRateLimit, isDevUnlimitedUser, requireUser } from "../../lib/auth.js";
import { MODEL_REGISTRY, resolveModelOverride, UnknownModelOverrideError } from "../../lib/models.js";
import { currentCredits, ensureUser, logCredit } from "../../lib/supabase.js";
import { bleedFlatten, capPixels, reapplyAlpha } from "../../lib/image.js";
import { resolveImageInput } from "../../lib/uploads.js";
import { ReplicateTimeoutError, upscale } from "../../lib/replicate.js";

export const config = {
  api: {
    bodyParser: { sizeLimit: "15mb" },
  },
};

/**
 * POST /v1/upscale — "Boost resolution" (E10.3, tiers E41.5).
 *
 * Body:    { image?: <base64 PNG with alpha>,        // legacy inline
 *            storage_key?: "<userId>/<uuid>.png",    // upload-bypass (groot beeld)
 *            quality?: "regular" | "high" }          // E41.5, default "regular"
 * Returns: 200 { cutout: <base64 PNG>, credits_remaining: int }
 *          402 insufficient_credits · 401 · 429 · 504
 *
 * Tiers (besluit Thierry 2026-07-12, zie plan/E41 41.5): "regular" =
 * google/upscaler x2 q100 voor 1 credit (vast $0,02/beeld); "high" =
 * Topaz High Fidelity V2 voor 3 credits, mét een 6 MP-input-cap zodat de
 * output ≤24 MP blijft en Topaz in de laagste unit ($0,05) valt. Zonder cap
 * schaalt Topaz' unit-billing met de output-megapixels en is elke run
 * verlieslatend. Dev-`model_override` blijft voorgaan op de tier-modelkeuze.
 *
 * Pipeline (zoals colorize, met credit-gate):
 *   1. bleedFlatten (E41.4): edge-bleed + flatten — upscalers negeren alpha,
 *      en een naive grijs-flatten bakt een grijze halo in zachte haarranden.
 *      Vooraf (E41.5): 6 MP-cap wanneer het resolved model Topaz is.
 *   2. Credit-gate (402 als leeg; alleen niet-dev betaalt).
 *   3. 2× fidelity-upscale op de RGB (tier-model).
 *   4. Hang het oorspronkelijke alfa er weer aan, herschaald naar de nieuwe
 *      maat (reapplyAlpha, lanczos3, zacht) — resultaat blijft een
 *      transparante cutout.
 *   5. Log de tier-credits, geef de grotere cutout terug.
 *
 * Fouten vóór de billable Replicate-call rekenen nooit af.
 */

/** E41.5: model + tarief per tier. Registry-refs, geen losse strings. */
const UPSCALE_TIERS = {
  regular: { modelKey: "google-upscaler", credits: 1 },
  high: { modelKey: "topaz", credits: 3 },
} as const;
type UpscaleQuality = keyof typeof UPSCALE_TIERS;

/** Input-cap voor het Topaz-pad: 6 MP × (2×)² = 24 MP output = laagste unit. */
const TOPAZ_MAX_INPUT_PIXELS = 6_000_000;
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

  // E41.5: tier-keuze. Onbekende waarde → 400 (geen stille fallback: de
  // client betaalt per tier, dus een typefout mag nooit een ander tarief
  // krijgen dan bedoeld).
  const rawQuality = req.body?.quality ?? "regular";
  if (rawQuality !== "regular" && rawQuality !== "high") {
    res.status(400).json({ error: "unknown_quality" });
    return;
  }
  const tier = UPSCALE_TIERS[rawQuality as UpscaleQuality];

  // E01.10: optionele model-override — dev-only, whitelist in MODEL_REGISTRY.
  // Zonder override bepaalt de tier het model.
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
  if (!modelRef) {
    modelRef = MODEL_REGISTRY.upscale.models[tier.modelKey].ref;
  }

  try {
    await ensureUser(user.id);

    // Step 1 (E41.5): kosten-cap vóór alles — Topaz rekent per output-MP.
    // Op het resolved model gekeyd zodat ook een dev-override naar Topaz
    // gecapt wordt en een override naar bv. real-esrgan niet.
    const cappedInput = modelRef.startsWith("topazlabs/")
      ? await capPixels(inputBytes, TOPAZ_MAX_INPUT_PIXELS)
      : inputBytes;

    // Edge-bleed + flatten (upscalers negeren alpha; E41.4). Pure
    // server-side beeldbewerking — veilig vóór de credit-gate.
    const flattened = await bleedFlatten(cappedInput);
    const flattenedDataUrl = `data:image/png;base64,${flattened.toString("base64")}`;

    // Step 2: credit-gate (alleen niet-dev).
    if (!isDevUser) {
      const credits = await currentCredits(user.id);
      if (credits < tier.credits) {
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
        delta: -tier.credits,
        reason: rawQuality === "high" ? "upscale_high" : "upscale",
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
