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
import { fetchActiveEffects, fetchActiveHairPresets, fetchActiveClothesPresets, fetchActiveFacePresets } from "../../lib/payload.js";
import { flattenOnGrey } from "../../lib/image.js";
import { resolveImageInput } from "../../lib/uploads.js";
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

/** Client-flag `soft_source`: bron is laag-res/soft → vraag scherpte in het resultaat. */
const SHARPNESS_CLAUSE =
  "If the source image is soft, blurry or low-resolution, render the styled result with crisp sharp detail — do not reproduce blur or softness from the input.";

/** Client-flag `preserve_framing`: stylize op volle origineel → geen reframe. */
const FRAMING_CLAUSE =
  "Keep the exact same crop, zoom, and position of the person in the frame — do not reframe, recenter, or change the composition.";

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
 * Hair-intent (E11.2). De E09.1-bakeoff koos nano-banana instruction-edit
 * voor kapselwissel (gezicht/expressie/kleding exact behouden). De clausule
 * spiegelt de winnende `edit-hair`-prompt. Twee paden, beide server-gemapt:
 *   - `hair_preset` → vaste prompt uit deze tabel;
 *   - `hair_prompt` → vrije kapselbeschrijving, in een VAST sjabloon gegoten
 *     (`HAIR_FREE_TEMPLATE`) zodat het een hair-only edit blijft — geen rauw
 *     promptveld op andermans Replicate-rekening.
 */
const HAIR_CLAUSE =
  "Keep the face, expression and clothing exactly the same. Change nothing else about the image.";

const HAIR_PRESETS: Record<string, string> = {
  "trim-flyaways":
    "Tidy up stray flyaway hairs and smooth the hairline for a neat, clean look, keeping the same hairstyle. " +
    HAIR_CLAUSE,
  curly:
    "Change the hairstyle to natural-looking curly hair in the person's own hair colour. " +
    HAIR_CLAUSE,
  straight:
    "Change the hairstyle to smooth, straight hair in the person's own hair colour. " +
    HAIR_CLAUSE,
  short:
    "Change the hairstyle to a short, neatly trimmed haircut in the person's natural hair colour. " +
    HAIR_CLAUSE,
  updo:
    "Change the hairstyle to an elegant updo with the hair tied up, in the person's own hair colour. " +
    HAIR_CLAUSE,
};

const HAIR_FREE_TEMPLATE = (desc: string) =>
  `Change the hairstyle to ${desc}. ` + HAIR_CLAUSE;

/**
 * Clothes-intent (E10.4). Besluit Thierry 2026-06-13: nano-banana
 * instruction-edit is het primaire kledingpad. De clausule is het harde
 * acceptatiecriterium — alléén de kleding wijzigt, gezicht/haar/pose/
 * achtergrond identiek. `clothes_preset` → vaste prompt; `clothes_prompt` →
 * vrije beschrijving in een vast clothes-only-sjabloon. (FLUX-Fill + mask
 * uit E10.1 blijft de precisie-fallback, niet hier.)
 */
const CLOTHES_CLAUSE =
  "Keep the face, hair, pose and background exactly the same. Change only the clothing, nothing else.";

const CLOTHES_PRESETS: Record<string, string> = {
  tshirt: "Change the upper clothing to a plain, well-fitted t-shirt. " + CLOTHES_CLAUSE,
  polo: "Change the upper clothing to a neat polo shirt. " + CLOTHES_CLAUSE,
  blazer: "Change the upper clothing to a tailored blazer over a shirt. " + CLOTHES_CLAUSE,
  hoody: "Change the upper clothing to a casual hoodie. " + CLOTHES_CLAUSE,
  sweater: "Change the upper clothing to a knitted sweater. " + CLOTHES_CLAUSE,
};

const CLOTHES_FREE_TEMPLATE = (desc: string) =>
  `Change the upper clothing to ${desc}. ` + CLOTHES_CLAUSE;

/**
 * Face beauty-intent (E32.1). Zelfde productie-`/v1/stylize` (nano-banana
 * instruction-edit). De E09.1-bakeoff koos nano-banana voor `edit-teeth`/
 * `edit-wrinkles` (subtielst, kader exact, "change nothing else" het best);
 * `apply-makeup` is nieuw en volgt dezelfde clausule. De clausule is het harde
 * acceptatiecriterium — alléén het gevraagde gezichtsdetail wijzigt, identiteit/
 * pose/haar/kleding/achtergrond identiek. Server-gemapt via `face_preset`; geen
 * vrij promptveld (productie blijft binnen deze whitelist).
 *
 * Teeth-fix uit de E09.1-bakeoff: de armen "tonen" tandenbleek soms door een
 * gesloten mond te openen → de whiten-teeth-prompt verbiedt expliciet het
 * openen van de mond / wijzigen van de expressie.
 */
const FACE_CLAUSE =
  "Keep the person's identity, facial structure, expression, pose, hair, " +
  "clothing and background exactly the same. Change only the requested facial " +
  "detail and nothing else, keeping the result photorealistic and natural.";

const FACE_PRESETS: Record<string, string> = {
  "whiten-teeth":
    "Subtly whiten and brighten the person's teeth for a natural, healthy " +
    "smile, without making them unnaturally white. Do not open the mouth or " +
    "change the expression; if the mouth is closed, leave it closed. " +
    FACE_CLAUSE,
  "apply-makeup":
    "Apply tasteful, natural-looking make-up: subtle foundation for an even " +
    "skin tone, soft blush, light eye make-up with mascara, and a natural " +
    "lipstick shade. Keep it understated and realistic. " +
    FACE_CLAUSE,
  "reduce-wrinkles":
    "Gently reduce fine lines and wrinkles on the face for a subtly refreshed " +
    "look, while preserving the person's age, character and natural skin " +
    "texture. Do not over-smooth the skin. " +
    FACE_CLAUSE,
};

/**
 * POST /v1/stylize — Effects (E09.2; productie sinds de promotie van het
 * dev-only E09.1-bakeoff-endpoint).
 *
 * Body:    { image?: <base64 PNG — cutout of vlak portret>,    // legacy inline
 *            storage_key?: "<userId>/<uuid>.png",            // upload-bypass (groot beeld)
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

  const isDevUser = isDevUnlimitedUser(user.email);

  // Prompt-bepaling, in volgorde: een Effects-`style` (E09.2), een hair-intent
  // (E11.2, `hair_preset`/`hair_prompt`), een clothes-intent (E10.4), een
  // face-intent (E32.1, `face_preset` — server-gemapt), of een vrij `prompt`
  // (alléén dev, bakeoff/handmatig testen).
  let prompt: string;
  let styleReferenceDataUrl: string | null = null;
  const styleKey = (req.body?.style ?? "") as string;
  const hairPreset = (req.body?.hair_preset ?? "") as string;
  const hairPrompt = (req.body?.hair_prompt ?? "") as string;
  const clothesPreset = (req.body?.clothes_preset ?? "") as string;
  const clothesPrompt = (req.body?.clothes_prompt ?? "") as string;
  const facePreset = (req.body?.face_preset ?? "") as string;
  const freePrompt = (req.body?.prompt ?? "") as string;
  if (styleKey) {
    // E33: Effects-stijlen zijn CMS-gestuurd. Zoek de key eerst in Payload op;
    // val terug op de hardgecodeerde STYLE_PROMPTS zodat de vier launch-keys
    // blijven werken tijdens het seed-venster (en als de CMS even onbereikbaar
    // is). STYLE_PROMPTS verdwijnt zodra de effecten in de CMS bevestigd zijn.
    const effects = await fetchActiveEffects();
    const effect = effects.find((e) => e.key === styleKey);
    const mapped = effect?.prompt ?? STYLE_PROMPTS[styleKey];
    if (!mapped) {
      res.status(400).json({ error: "unknown_style" });
      return;
    }
    prompt = mapped;
    // Fetch the style reference image if the CMS effect has one, so it can be
    // passed to the model as a visual style guide alongside the prompt.
    if (effect?.styleReferenceUrl) {
      try {
        const refRes = await fetch(effect.styleReferenceUrl);
        if (refRes.ok) {
          const buf = Buffer.from(await refRes.arrayBuffer());
          const mime = refRes.headers.get("content-type") ?? "image/jpeg";
          styleReferenceDataUrl = `data:${mime};base64,${buf.toString("base64")}`;
        }
      } catch {
        // Soft-fail: no reference is better than aborting the stylize call.
      }
    }
  } else if (hairPreset) {
    // CMS-first: try Payload, fall back to hardcoded HAIR_PRESETS.
    const cmsPresets = await fetchActiveHairPresets();
    const mapped = cmsPresets.find((p) => p.key === hairPreset)?.prompt ?? HAIR_PRESETS[hairPreset];
    if (!mapped) {
      res.status(400).json({ error: "unknown_hair_preset" });
      return;
    }
    prompt = mapped;
  } else if (hairPrompt) {
    // Vrije kapselbeschrijving: in een vast hair-only-sjabloon gegoten, niet
    // als rauwe instructie. Strak begrensd op lengte.
    if (typeof hairPrompt !== "string" || hairPrompt.length > 200) {
      res.status(400).json({ error: "missing_or_oversized_prompt" });
      return;
    }
    prompt = HAIR_FREE_TEMPLATE(hairPrompt.trim());
  } else if (clothesPreset) {
    // CMS-first: try Payload, fall back to hardcoded CLOTHES_PRESETS.
    const cmsPresets = await fetchActiveClothesPresets();
    const mapped = cmsPresets.find((p) => p.key === clothesPreset)?.prompt ?? CLOTHES_PRESETS[clothesPreset];
    if (!mapped) {
      res.status(400).json({ error: "unknown_clothes_preset" });
      return;
    }
    prompt = mapped;
  } else if (clothesPrompt) {
    // Vrije kledingbeschrijving: in een vast clothes-only-sjabloon gegoten.
    if (typeof clothesPrompt !== "string" || clothesPrompt.length > 200) {
      res.status(400).json({ error: "missing_or_oversized_prompt" });
      return;
    }
    prompt = CLOTHES_FREE_TEMPLATE(clothesPrompt.trim());
  } else if (facePreset) {
    // CMS-first: try Payload, fall back to hardcoded FACE_PRESETS.
    const cmsPresets = await fetchActiveFacePresets();
    const mapped = cmsPresets.find((p) => p.key === facePreset)?.prompt ?? FACE_PRESETS[facePreset];
    if (!mapped) {
      res.status(400).json({ error: "unknown_face_preset" });
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
    // Niet-dev zonder geldige intent, of dev zonder enige prompt.
    res.status(400).json({ error: "unknown_style" });
    return;
  }

  if (req.body?.soft_source === true) {
    prompt = `${prompt} ${SHARPNESS_CLAUSE}`;
  }
  if (req.body?.preserve_framing === true) {
    prompt = `${prompt} ${FRAMING_CLAUSE}`;
  }

  // Input image: inline base64 (legacy) of een Storage-upload (storage_key,
  // omzeilt de 4.5 MB body-cap). Ná de intent-validatie zodat een ongeldige
  // intent de upload niet verbruikt.
  const inputBytes = await resolveImageInput(req, res, user.id);
  if (!inputBytes) return;

  // Modelkeuze, in volgorde van precedentie:
  //   1. E01.10 dev-only `model_override` (hele whitelist) — wint altijd;
  //   2. E15.6 gebruikersgerichte `generation_model` (nano / OpenAI);
  //   3. anders de feature-default (nano-banana).
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
  if (!modelRef) {
    modelRef = resolveGenerationModel("stylize", req.body?.generation_model);
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
      styleReferenceDataUrl,
      width: meta.width ?? 0,
      height: meta.height ?? 0,
      model: modelRef,
    });
    const download = await fetch(resultUrl);
    if (!download.ok) {
      throw new Error(`stylize result fetch failed: ${download.status}`);
    }
    const resultBytes = Buffer.from(await download.arrayBuffer());
    const resultMeta = await sharp(resultBytes).metadata();
    const inputW = meta.width ?? 0;
    const inputH = meta.height ?? 0;
    const outputW = resultMeta.width ?? 0;
    const outputH = resultMeta.height ?? 0;
    const cutoutW = Number(req.body?.cutout_w) || 0;
    const cutoutH = Number(req.body?.cutout_h) || 0;
    console.info(
      `[stylize_dims] input=${inputW}x${inputH} output=${outputW}x${outputH}` +
        (cutoutW > 0 ? ` cutout=${cutoutW}x${cutoutH}` : ""),
    );

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
      input_width: inputW,
      input_height: inputH,
      output_width: outputW,
      output_height: outputH,
    });
  } catch (err) {
    // Log the message only — the Replicate SDK embeds the auth header in the
    // full error object, so logging `err` whole leaks REPLICATE_API_TOKEN.
    const msg = err instanceof Error ? err.message : String(err);
    console.error("/v1/stylize error:", msg);
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
    res.status(500).json({ error: "stylize_failed" });
  }
}
