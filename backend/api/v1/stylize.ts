import type { VercelRequest, VercelResponse } from "@vercel/node";
import sharp from "sharp";
import { checkRateLimit, requireUser } from "../../lib/auth.js";
import {
  defaultModelRef,
  MODEL_REGISTRY,
  modelFixedAspects,
  resolveGenerationModel,
  resolveModelOverride,
  UnknownModelOverrideError,
} from "../../lib/models.js";
import { proOverrideFor } from "../../lib/proAccess.js";
import { activeSubscription, currentCredits, ensureCompedCredits, ensureUser, logCredit } from "../../lib/supabase.js";
import { fetchActiveEffects, fetchActiveHairPresets, fetchActiveClothesPresets, fetchActiveFacePresets, thumbnailVariant } from "../../lib/payload.js";
import { downloadReferenceBytes, getCustomEffect } from "../../lib/customEffects.js";
import { FRAMING_CLAUSE, STYLE_REFERENCE_CLAUSE, DIE_CUT_COMPOSITION_CLAUSE, isDieCutStyle } from "../../lib/stylizePrompts.js";
import {
  type AspectPad,
  capLongEdge,
  cropBackFromPad,
  flattenOnGrey,
  nearestFixedAspect,
  padToAspect,
} from "../../lib/image.js";
import { resolveImageInput, uploadResultImage } from "../../lib/uploads.js";
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

/**
 * Custom-effect prompt (E34). The FIRST image is the portrait to restyle; the
 * SECOND image is the user's style reference. The template is the hard frame
 * around the user's free-text description — it pins the roles of the two
 * images (edit the first, borrow the look of the second; do NOT paste the
 * reference's subject/composition) and reuses the identity clause so the
 * person stays recognizable. The description is sandwiched, never the whole
 * instruction, so a user can't repurpose the call into an arbitrary edit.
 */
const CUSTOM_STYLE_TEMPLATE = (description: string) => {
  const refinement = description ? `Style direction: ${description}. ` : "";
  return (
    "Restyle the first image (the portrait). Apply the visual style, colour " +
    "palette, materials, texture and artistic technique of the second image " +
    "to it as a STYLE REFERENCE only — do not copy the subject, face, pose or " +
    "composition of the second image. " +
    refinement +
    IDENTITY_CLAUSE
  );
};

/** Client-flag `soft_source`: bron is laag-res/soft → vraag scherpte in het resultaat. */
const SHARPNESS_CLAUSE =
  "If the source image is soft, blurry or low-resolution, render the styled result with crisp sharp detail — do not reproduce blur or softness from the input.";

// FRAMING_CLAUSE + STYLE_REFERENCE_CLAUSE leven sinds E55.7 in
// lib/stylizePrompts.ts (side-effect-vrij) zodat de bakeoff-driver ze deelt.

/** Max referenties richting het model; meer verwatert identity-behoud. */
const STYLE_REF_MAX = 3;

/**
 * E55.1: cap op de langste zijde vóór flatten/pad. Sluit aan op de
 * client-cap (StylizeQuality, 2048) en de cutout-norm; belt-and-braces
 * voor oudere clients die nog full-res uploaden.
 */
const STYLIZE_INPUT_MAX_EDGE = 2048;

/**
 * In-process cache van referentie-data-URLs. Referenties wijzigen alleen bij
 * een CMS-edit, dus een warme Vercel-instance hoeft ze niet per generatie
 * opnieuw te downloaden. TTL ruim boven de 60s effects-cache is prima: de
 * URL is content-addressed per upload (nieuwe upload = nieuwe URL).
 */
const styleRefCache = new Map<string, { expiresAt: number; dataUrl: string }>();
const STYLE_REF_CACHE_TTL_MS = 10 * 60_000;

async function fetchStyleReferences(urls: string[]): Promise<string[]> {
  const now = Date.now();
  const results = await Promise.all(
    urls.slice(0, STYLE_REF_MAX).map(async (url) => {
      // Verkleind ophalen via de Supabase image-transformatie (E52.1-patroon):
      // CMS-uploads kunnen multi-MB zijn; ~1024px is zat als stijlvoorbeeld.
      const scaled = thumbnailVariant(url, 1024, 85) ?? url;
      const hit = styleRefCache.get(scaled);
      if (hit && hit.expiresAt > now) return hit.dataUrl;
      try {
        const res = await fetch(scaled);
        if (!res.ok) return null;
        const buf = Buffer.from(await res.arrayBuffer());
        const mime = res.headers.get("content-type") ?? "image/jpeg";
        const dataUrl = `data:${mime};base64,${buf.toString("base64")}`;
        styleRefCache.set(scaled, { expiresAt: now + STYLE_REF_CACHE_TTL_MS, dataUrl });
        return dataUrl;
      } catch {
        // Soft-fail per referentie: minder referenties is beter dan een
        // mislukte generatie.
        return null;
      }
    }),
  );
  return results.filter((r): r is string => r !== null);
}

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
 * E55-edge (Thierry, 2026-08-03): een edit op een GESTYLEDE basis (3d-head,
 * sticker, …) rendde de wijziging fotorealistisch — een katoenen bucket hat
 * op een 3D-toy-render. Elke edit-intent krijgt daarom deze stijlmatch-
 * clausule: op een foto is 'ie een no-op, op een gestylede basis dwingt 'ie
 * de wijziging in dezelfde stijl.
 */
const STYLE_MATCH_CLAUSE =
  "Render the change in the same visual style as the rest of the image: photorealistic only if the image itself is photorealistic; if the image is a stylized illustration, cartoon or 3D render, render the change in exactly that style.";

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

// Let op: fetchActiveFacePresets() is CMS-first — bestaat er ooit een
// `face-presets` Payload-collectie (vandaag niet), dan overschrijft die
// deze teksten stilzwijgend. E32.4: de whiten-teeth-prompt is herschreven
// zonder het woord "brighten" — zonder mask is dat een globale attractor
// (het hele beeld kwam lichter terug); het verbod op globale wijzigingen
// is nu expliciet.
const FACE_PRESETS: Record<string, string> = {
  "whiten-teeth":
    "Whiten the teeth naturally, keeping realistic enamel texture — not " +
    "paper-white. Change nothing else about the image: do not brighten, " +
    "lighten or recolour the skin, lips, lighting or background. Do not " +
    "open the mouth or change the expression; if the mouth is closed and " +
    "no teeth are visible, return the image unchanged. " +
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
 *          422 generation_refused (moderatie/safety-weigering; geen credit verbruikt)
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

  // E14.9 — the Pro list: CMS `pro-access` first, DEV_UNLIMITED_EMAILS as
  // break-glass. "unlimited" skips credit accounting entirely; a comped Pro
  // gets this month's allowance and then spends credits like anyone else.
  const override = await proOverrideFor(user.email);
  const isDevUser = override?.mode === "unlimited";
  if (override?.mode === "pro") {
    await ensureCompedCredits(user.id, override.monthlyCredits);
  }

  // Modelkeuze VÓÓR de prompt-opbouw (E55-uitrol-fix): de refs-beslissing in
  // de style-tak hangt van de engine af. Precedentie ongewijzigd:
  //   1. E01.10 dev-only `model_override` (hele whitelist) — wint altijd;
  //   2. E15.6 gebruikersgerichte `generation_model` (nano / OpenAI);
  //   3. anders de feature-default (gpt-image-2, env-overridable).
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
  // E55-edge-sweep: de default-flip geldt voor de Effects-intents; de
  // edit-intents (hair/clothes/face) houden hun E09.1-winnaar nano-banana.
  const isEditIntent = Boolean(
    (req.body?.hair_preset ?? "") || (req.body?.hair_prompt ?? "") ||
    (req.body?.clothes_preset ?? "") || (req.body?.clothes_prompt ?? "") ||
    (req.body?.face_preset ?? ""),
  );
  if (!modelRef && isEditIntent) {
    modelRef = MODEL_REGISTRY.stylize.models["nano-banana"].ref;
  }
  const effectiveRef = modelRef ?? defaultModelRef("stylize");
  // E55.7/E54-les, live bevestigd bij de uitrol (2026-08-03): CMS-stijl-
  // referenties helpen gpt-image maar SCHADEN nano-banana (stijltrouw zakt én
  // nano volgt de ratio van een referentie i.p.v. de input — 1733x1155 in,
  // 896x1152 uit). Oude app-builds sturen expliciet "nano-banana" mee, dus
  // deze guard is nodig zolang die bestaan; een expliciete nano-keuze in
  // Settings hoort 'm ook. Custom effects vallen hier bewust BUITEN: hun ene
  // referentie is integraal onderdeel van de E34-flow (CUSTOM_STYLE_TEMPLATE).
  const engineAcceptsStyleRefs = effectiveRef.startsWith("openai/gpt-image");

  // Prompt-bepaling, in volgorde: een Effects-`style` (E09.2), een hair-intent
  // (E11.2, `hair_preset`/`hair_prompt`), een clothes-intent (E10.4), een
  // face-intent (E32.1, `face_preset` — server-gemapt), of een vrij `prompt`
  // (alléén dev, bakeoff/handmatig testen).
  let prompt: string;
  // Stijlreferenties richting het model: CMS-referenties per effect (E54) óf
  // de ene referentie-afbeelding van een user-created custom effect (E34).
  // Blijft leeg voor alle andere intents.
  let styleReferenceDataUrls: string[] = [];
  const customEffectId = (req.body?.custom_effect_id ?? "") as string;
  const styleKey = (req.body?.style ?? "") as string;
  const hairPreset = (req.body?.hair_preset ?? "") as string;
  const hairPrompt = (req.body?.hair_prompt ?? "") as string;
  const clothesPreset = (req.body?.clothes_preset ?? "") as string;
  const clothesPrompt = (req.body?.clothes_prompt ?? "") as string;
  const facePreset = (req.body?.face_preset ?? "") as string;
  const freePrompt = (req.body?.prompt ?? "") as string;
  if (customEffectId) {
    // E34: user-created custom effect. Pro-only (de capability is Pro), eigenaar-
    // gescoped. De prompt = de opgeslagen beschrijving in een vast sjabloon; de
    // referentie-afbeelding gaat als tweede beeld mee naar het model.
    const isPro = override !== null || (await activeSubscription(user.id)) !== null;
    if (!isPro) {
      res.status(403).json({ error: "pro_required" });
      return;
    }
    const effect = await getCustomEffect(user.id, customEffectId);
    if (!effect) {
      res.status(400).json({ error: "unknown_custom_effect" });
      return;
    }
    prompt = CUSTOM_STYLE_TEMPLATE(effect.prompt);
    try {
      const refBytes = await downloadReferenceBytes(effect.reference_path);
      // Zelfde kanaal als de CMS-referenties (E54): het portret blijft het
      // eerste beeld, de referentie gaat als tweede mee. De rolclausule zit
      // hier al in CUSTOM_STYLE_TEMPLATE zelf.
      styleReferenceDataUrls = [`data:image/png;base64,${refBytes.toString("base64")}`];
    } catch (e) {
      console.error(
        "/v1/stylize custom reference fetch failed:",
        e instanceof Error ? e.message : String(e),
      );
      res.status(500).json({ error: "reference_fetch_failed" });
      return;
    }
  } else if (styleKey) {
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
    // E54: CMS-stijlreferenties meesturen als visuele stijlgids naast de
    // prompt — maar alléén op engines waar ze aantoonbaar helpen (gpt-image;
    // zie de engineAcceptsStyleRefs-guard hierboven). De rolclausule alléén
    // toevoegen als er echt referenties meegaan.
    if (effect && effect.styleReferenceUrls.length > 0 && engineAcceptsStyleRefs) {
      styleReferenceDataUrls = await fetchStyleReferences(effect.styleReferenceUrls);
      if (styleReferenceDataUrls.length > 0) {
        prompt = `${prompt} ${STYLE_REFERENCE_CLAUSE}`;
      }
    }
    // Die-cut-stijl (sticker): gesloten vorm, gecentreerd met marge — en
    // hieronder GEEN framing-clausule (zie lib/stylizePrompts.ts). Volgorde
    // = composeEffectPrompt (bakeoff-driver); hier los uitgeschreven omdat
    // de refs-fetch async tussen de clausules zit.
    if (isDieCutStyle(styleKey)) {
      prompt = `${prompt} ${DIE_CUT_COMPOSITION_CLAUSE}`;
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

  // E55-edge: edits moeten de stijl van de basis volgen (zie STYLE_MATCH_CLAUSE).
  if (isEditIntent) {
    prompt = `${prompt} ${STYLE_MATCH_CLAUSE}`;
  }

  if (req.body?.soft_source === true) {
    prompt = `${prompt} ${SHARPNESS_CLAUSE}`;
  }
  // Die-cut-stijlen negeren preserve_framing bewust: de client stuurt 'm
  // hard aan voor élk effect, maar een sticker moet juist mógen herkadreren.
  if (req.body?.preserve_framing === true && !isDieCutStyle(styleKey)) {
    prompt = `${prompt} ${FRAMING_CLAUSE}`;
  }

  // Input image: inline base64 (legacy) of een Storage-upload (storage_key,
  // omzeilt de 4.5 MB body-cap). Ná de intent-validatie zodat een ongeldige
  // intent de upload niet verbruikt.
  const inputBytes = await resolveImageInput(req, res, user.id);
  if (!inputBytes) return;

  try {
    await ensureUser(user.id);

    // Server-side voorwerk vóór de credit-gate: cap op 2048 lange zijde
    // (E55.1 — modellen leveren toch ~1–1.5 MP; groter = alleen latency)
    // en flatten op grijs.
    const capped = await capLongEdge(inputBytes, STYLIZE_INPUT_MAX_EDGE);
    const flattened = await flattenOnGrey(capped);
    const meta = await sharp(flattened).metadata();
    const inputW = meta.width ?? 0;
    const inputH = meta.height ?? 0;

    // E55.1 aspect-contract: modellen met een vaste ratio-set (gpt-image)
    // krijgen een naar die ratio gepadde input; het resultaat wordt na afloop
    // proportioneel teruggesneden. Response-ratio == input-ratio, altijd. De
    // set komt per model uit de registry (2.0 kent er meer dan 1.5, dus padt
    // dunner tot niets).
    const fixedAspects = modelFixedAspects(effectiveRef);
    let pad: AspectPad | null = null;
    let modelPng = flattened;
    if (fixedAspects && inputW > 0 && inputH > 0) {
      const target = nearestFixedAspect(inputW, inputH, fixedAspects);
      pad = await padToAspect(flattened, target.ratio);
      modelPng = pad.padded;
    }
    const flatDataUrl = `data:image/png;base64,${modelPng.toString("base64")}`;

    // Credit-gate (alleen niet-dev), net als colorize.
    if (!isDevUser) {
      const credits = await currentCredits(user.id);
      if (credits < MODEL_REGISTRY.stylize.credits) {
        res.status(402).json({ error: "insufficient_credits", credits_remaining: 0 });
        return;
      }
    }

    const modelStart = Date.now();
    const resultUrl = await stylizeEdit({
      imageDataUrl: flatDataUrl,
      prompt,
      styleReferenceDataUrls,
      width: pad?.canvasW ?? inputW,
      height: pad?.canvasH ?? inputH,
      model: modelRef,
    });
    const modelMs = Date.now() - modelStart;
    const download = await fetch(resultUrl);
    if (!download.ok) {
      throw new Error(`stylize result fetch failed: ${download.status}`);
    }
    let resultBytes: Buffer = Buffer.from(await download.arrayBuffer());
    if (pad) {
      resultBytes = await cropBackFromPad(resultBytes, pad);
    }
    const resultMeta = await sharp(resultBytes).metadata();
    const outputW = resultMeta.width ?? 0;
    const outputH = resultMeta.height ?? 0;
    const cutoutW = Number(req.body?.cutout_w) || 0;
    const cutoutH = Number(req.body?.cutout_h) || 0;
    console.info(
      `[stylize_dims] input=${inputW}x${inputH} output=${outputW}x${outputH}` +
        ` model=${effectiveRef} model_ms=${modelMs} pad=${pad ? 1 : 0}` +
        ` refs=${styleReferenceDataUrls.length}` +
        (cutoutW > 0 ? ` cutout=${cutoutW}x${cutoutH}` : ""),
    );

    // E55-delivery-fix (live gezien 2026-08-03): gpt-image-2-PNG's kunnen als
    // base64 Vercels ~4.5MB-response-cap overschrijden → stil afgekapte body,
    // decode-fout in de app, en een generatie die wél gefactureerd werd. Grote
    // resultaten gaan daarom via een signed Storage-URL (E42-patroon), en de
    // upload gebeurt VÓÓR logCredit — een niet-leverbaar resultaat mag nooit
    // een credit kosten. Kleine resultaten blijven inline (oude clients).
    const base64 = resultBytes.toString("base64");
    const INLINE_BASE64_MAX = 3_200_000;
    let resultDeliveryUrl: string | null = null;
    let ledgerRef = resultUrl;
    if (base64.length > INLINE_BASE64_MAX) {
      const uploaded = await uploadResultImage(user.id, resultBytes, "png");
      resultDeliveryUrl = uploaded.url;
      ledgerRef = uploaded.key;
    }

    if (!isDevUser) {
      await logCredit({
        userId: user.id,
        delta: -MODEL_REGISTRY.stylize.credits,
        reason: "stylize",
        ref: ledgerRef,
      });
    }

    const creditsRemaining = isDevUser ? 999 : await currentCredits(user.id);
    res.status(200).json({
      ...(resultDeliveryUrl ? { image_url: resultDeliveryUrl } : { image: base64 }),
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
    // E55.1: moderatie/safety-weigering (gpt-image weigert soms portretten,
    // ook op moderation=low) → getypte fout i.p.v. generieke 500. Credits
    // zijn veilig: logCredit draait pas ná een geslaagde generatie.
    if (/sensitiv|content.?polic|moderation|flagged|safety|refus/i.test(msg)) {
      res.status(422).json({ error: "generation_refused" });
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
