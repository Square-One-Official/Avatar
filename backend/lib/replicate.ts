import Replicate from "replicate";
import { GPT_IMAGE_ASPECTS } from "./aspects.js";
import { nearestFixedAspect } from "./image.js";
import { defaultModelRef, modelFixedAspects } from "./models.js";

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN! });

/**
 * Hard timeout for any single `replicate.run()` call (audit MEDIUM #17).
 * The SDK has no built-in client-side timeout; a hung Replicate prediction
 * would otherwise let the Vercel function run to its `maxDuration`,
 * costing the user a full timeout instead of a clean 504.
 *
 * 50s is the DEFAULT budget, sized for the endpoints on a 60s `maxDuration`
 * (vercel.json: cutout) — ~10s headroom so the handler can still finalise
 * (free-trial counter, response write) after we surface the timeout.
 * Features whose model legitimately runs longer get a per-feature budget
 * instead: `STYLIZE_TIMEOUT_MS`, `BACKGROUND_TIMEOUT_MS` and
 * `COLORIZE_TIMEOUT_MS` (80s, under their 90s `maxDuration`). E44.1: don't
 * reuse this default for a slow model — DeOldify cold starts sat right at
 * the 50s edge and died as silent 504s.
 */
const REPLICATE_TIMEOUT_MS = 50_000;

export class ReplicateTimeoutError extends Error {
  // E55.7-fix: meld de ÉCHTE gebruikte timeout — de message hardcodede de
  // 50s-default en loog dus bij features met een eigen budget (stylize 80s).
  constructor(public readonly model: string, timeoutMs: number = REPLICATE_TIMEOUT_MS) {
    super(`replicate.run(${model}) timed out after ${timeoutMs}ms`);
    this.name = "ReplicateTimeoutError";
  }
}

async function runWithTimeout<T>(
  model: string,
  p: Promise<T>,
  timeoutMs: number = REPLICATE_TIMEOUT_MS,
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      p,
      new Promise<T>((_, reject) => {
        timer = setTimeout(() => reject(new ReplicateTimeoutError(model, timeoutMs)), timeoutMs);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

/**
 * Transient upstream gateway statuses — Replicate sits behind Cloudflare, so
 * a brief blip surfaces as a 502/503/504 (or a Cloudflare 52x) *before* a
 * prediction is created. These are safe to retry: no prediction was started,
 * so there's no double-billing. A persistent outage still fails after the
 * retries are exhausted.
 */
const TRANSIENT_UPSTREAM_STATUS = new Set([502, 503, 504, 520, 521, 522, 523, 524]);

function isTransientUpstream(err: unknown): boolean {
  const status = (err as { response?: { status?: number } } | null)?.response?.status;
  return typeof status === "number" && TRANSIENT_UPSTREAM_STATUS.has(status);
}

/**
 * Run a Replicate call with our hard timeout plus a small retry on transient
 * upstream gateway errors (audit MEDIUM #17 follow-up). Takes a THUNK (not a
 * started promise) so each attempt is a fresh request. Never retries our own
 * timeout (no budget left under the function's maxDuration) or a real model
 * error — only the fast gateway 5xx that come back before any work is done.
 */
async function runWithRetry<T>(
  model: string,
  thunk: () => Promise<T>,
  timeoutMs: number = REPLICATE_TIMEOUT_MS,
  maxAttempts = 2,
): Promise<T> {
  for (let attempt = 1; ; attempt++) {
    try {
      return await runWithTimeout(model, thunk(), timeoutMs);
    } catch (err) {
      if (
        attempt >= maxAttempts ||
        err instanceof ReplicateTimeoutError ||
        !isTransientUpstream(err)
      ) {
        throw err;
      }
      console.warn(`[replicate] ${model} transient upstream error, retry ${attempt}/${maxAttempts - 1}`);
      await new Promise((r) => setTimeout(r, 700 * attempt));
    }
  }
}

/**
 * Magic Cutout — runs a background-removal model on the input portrait.
 * Returns the URL of the resulting transparent-PNG. The caller downloads it
 * and re-encodes for the client.
 *
 * Default model: BiRefNet (Bilateral Reference Network), the academic
 * gold-standard for portrait matting — fine alpha at hair boundaries that
 * the cheaper alternatives (transparent-background, tracer_b7, U2Net)
 * can't match. ~$0.0017 per call. The ref (incl. pinned version) lives in
 * MODEL_REGISTRY (lib/models.ts); `model` accepts a whitelisted override
 * ref from `resolveModelOverride` (E01.10) and must point to a model that
 * takes the same input payload.
 */
export async function magicCutout(input: {
  imageDataUrl: string;
  model?: string | null;
}): Promise<string> {
  const output = (await runWithRetry(
    "magicCutout",
    () => replicate.run((input.model ?? defaultModelRef("cutout")) as `${string}/${string}`, {
      input: {
        image: input.imageDataUrl,
        // 2048x2048 is the practical upper bound — BiRefNet runs at this on a
        // T4 in <10s. Larger inputs are bilinear-upscaled internally and don't
        // sharpen the matte further. The client already caps long-edge at the
        // canvas-friendly 2048 before sending.
        resolution: "2048x2048",
      },
    }),
  )) as unknown;

  return extractUrl(output, "magicCutout");
}

/**
 * Outpaint a portrait using FLUX.1 Fill (Pro) — the inpainting/outpainting
 * variant of Flux. Unlike instruction-edit models (Kontext, Nano Banana),
 * this is the right tool for "extend the canvas around a subject":
 *
 *   - `image`: a padded RGB canvas with the original person composited
 *     over a neutral grey backdrop. The original pixels are untouched.
 *   - `mask`: white where the model must generate (the padded margin),
 *     black where it must preserve the input (the existing silhouette).
 *
 * The model only paints into the masked region, so the face/hair/clothing
 * pixels are guaranteed to round-trip unchanged — no identity drift, no
 * second-subject hallucinations, no flatten-then-regenerate seam.
 *
 * The default ref (black-forest-labs/flux-fill-pro) lives in MODEL_REGISTRY
 * (lib/models.ts); `model` accepts a whitelisted override ref from
 * `resolveModelOverride` (E01.10) with the same input contract.
 */
export async function outpaintPortrait(input: {
  imageDataUrl: string;
  maskDataUrl: string;
  model?: string | null;
}): Promise<string> {
  // Negative phrasing matters: without "no objects/props/hands/etc"
  // the model will happily invent context to fill the margin (an
  // earlier version produced a microphone-stick on one side). Repeat
  // the empty-background directive — FLUX responds to emphasis.
  //
  // The face-preservation clause is absolute: even if part of the face
  // is missing or cropped, the model must NOT invent or modify facial
  // features. The mask already enforces this physically (face zone is
  // black = preserve), but stating the rule in the prompt is a second
  // safety net for any feathered seam pixels near the face.
  const prompt =
    "A studio portrait of one person, head and upper chest only, " +
    "centered. Plain empty neutral grey background, completely empty, " +
    "no objects, no props, no microphone, no instruments, no hands raised, " +
    "no accessories, no other people, no text. Keep the face, hair, skin, " +
    "and clothing untouched. Do not modify the face under any circumstances; " +
    "if any part of the face appears missing or incomplete, leave it as is — " +
    "do not invent, redraw, or extend facial features. " +
    "Photographic, soft natural lighting, single subject.";

  const output = (await runWithRetry(
    "outpaintPortrait",
    () => replicate.run((input.model ?? defaultModelRef("fill_body")) as `${string}/${string}`, {
      input: {
        image: input.imageDataUrl,
        mask: input.maskDataUrl,
        prompt,
        output_format: "png",
        // Max permitted with an input image. Lower values may refuse on
        // perfectly innocuous portraits.
        safety_tolerance: 2,
      },
    }),
  )) as unknown;

  return extractUrl(output, "outpaintPortrait");
}

/**
 * Colorize — runs DeOldify on a B&W (or low-saturation) photo and returns
 * a colorized RGB version. The caller is responsible for compositing the
 * input cutout over an opaque background BEFORE sending (DeOldify operates
 * on RGB only and will silently flatten any alpha) and for re-attaching
 * the alpha channel afterwards. Same dimensions in/out.
 *
 * Default model: DeOldify, the long-running standard for B&W photo
 * colorization. Warm photo-realistic palette, ~$0.001 per call.
 * `model_name: "Artistic"` lifts saturation slightly for portraits (the
 * alternative "Stable" is tuned for landscapes and leaves portraits
 * looking washed-out). `render_factor` is a quality knob: 35 is the
 * documented sweet spot — higher sharpens detail at the cost of speed/$
 * but rarely changes the colour decisions on a portrait.
 *
 * The ref (incl. pinned version) lives in MODEL_REGISTRY (lib/models.ts);
 * `model` accepts a whitelisted override ref from `resolveModelOverride`
 * (E01.10) with the same input contract.
 *
 * Ruimere timeout dan de 50s-default (E44.1, audit B2): DeOldify op
 * `render_factor: 35` + een cold start zit geregeld tegen/over de 50s,
 * waardoor legitieme runs als 504 stierven — geen resultaat, geen credit,
 * maar ook geen zichtbare fout. vercel.json geeft colorize 90s
 * `maxDuration`; 80s laat 10s marge voor het afronden van de response
 * (zelfde verhouding als STYLIZE_TIMEOUT_MS).
 */
const COLORIZE_TIMEOUT_MS = 80_000;

export async function colorize(input: {
  imageDataUrl: string;
  model?: string | null;
}): Promise<string> {
  const output = (await runWithRetry(
    "colorize",
    () => replicate.run((input.model ?? defaultModelRef("colorize")) as `${string}/${string}`, {
      input: {
        input_image: input.imageDataUrl,
        model_name: "Artistic",
        render_factor: 35,
      },
    }),
    COLORIZE_TIMEOUT_MS,
  )) as unknown;

  return extractUrl(output, "colorize");
}

/**
 * Upscale (E10.3, "Boost resolution") — Real-ESRGAN op een geflattende RGB.
 * Werkt op de op-grijs-geflattende cutout (Real-ESRGAN negeert alpha); de
 * endpoint hangt het oorspronkelijke alfa er ná weer aan (op de nieuwe maat).
 * `scale` = 2 (genoeg "boost" zonder de outputmaat te laten ontploffen).
 */
export async function upscale(input: {
  imageDataUrl: string;
  model?: string | null;
}): Promise<string> {
  const ref = input.model ?? defaultModelRef("upscale");
  const output = (await runWithRetry(
    "upscale",
    () => replicate.run(ref as `${string}/${string}`, {
      input: upscaleInputFor(ref, input.imageDataUrl),
    }),
  )) as unknown;

  return extractUrl(output, "upscale");
}

/**
 * Per-model input-vertaling voor de upscaler (E41.1 + E41.4; spiegelt
 * stylizeInputFor). Identiteit gaat vóór scherpte: geen generatieve
 * gezichts-"verbetering" — GFPGAN-achtige reconstructie maakt huid glad en
 * gumt sproeten/sieraden weg (kwaliteitsklacht 2026-07-03). Onbekende refs
 * vallen op de Real-ESRGAN-vorm terug.
 */
function upscaleInputFor(ref: string, imageDataUrl: string): Record<string, unknown> {
  if (ref.startsWith("topazlabs/image-upscale")) {
    // High Fidelity V2 = de detail-behoudende Gigapixel-variant;
    // face_enhancement bewust uit. PNG voorkomt JPEG-randartefacten vlak
    // vóór de alpha-reapply.
    return {
      image: imageDataUrl,
      enhance_model: "High Fidelity V2",
      upscale_factor: "2x",
      face_enhancement: false,
      output_format: "png",
    };
  }
  if (ref.startsWith("google/upscaler")) {
    // Output is JPEG; default compression_quality 80 bakt compressieruis in
    // de haarranden → maximaal.
    return { image: imageDataUrl, upscale_factor: "x2", compression_quality: 100 };
  }
  if (ref.startsWith("philz1337x/crystal-upscaler")) {
    return { image: imageDataUrl, scale_factor: 2 };
  }
  // Real-ESRGAN (huidige default) & onbekend: face_enhance UIT — de E41.1-
  // stand (aan) bleek de gladde-huid/weg-oorbellen-oorzaak.
  return { image: imageDataUrl, scale: 2, face_enhance: false };
}

/**
 * Stylize — instruction-edit on a flattened RGB portrait (stijlen én
 * retouch-edits). In tegenstelling tot outpaintPortrait is er geen mask:
 * het model herschrijft het hele beeld op basis van de prompt, dus
 * identity-behoud is hier een modeleigenschap, niet een pixelgarantie —
 * precies wat de E09.1-bakeoff meet.
 *
 * De drie geregistreerde armen (MODEL_REGISTRY.stylize) accepteren NIET
 * dezelfde payload; stylizeInputFor vertaalt per model-familie. Een nieuw
 * alternatief registreren = eerst hier een tak toevoegen (zie de NOTE in
 * lib/models.ts).
 *
 * Ruimere timeout dan de 50s-default, gedimensioneerd op de E55.7-meting
 * (2026-08-03): gpt-image-2 medium p50 65s / p95 75s met één 149s-
 * uitschieter → 160s dekt de staart. De endpoint-maxDuration (180s,
 * vercel.json) houdt 20s marge voor refs-fetch, pad/crop en de response.
 */
const STYLIZE_TIMEOUT_MS = 160_000;

export async function stylizeEdit(input: {
  imageDataUrl: string;
  prompt: string;
  /** Breedte/hoogte van de input, voor armen zonder match_input_image. */
  width: number;
  height: number;
  model?: string | null;
  /** Optioneel: data-URLs van voorbeeld-outputs die het model als visuele
   *  stijlreferenties meekrijgt naast de prompt. Gebruikt door Effects (E54)
   *  én door user-created custom effects (E34 — precies één referentie); de
   *  prompt bevat dan de rolclausule (eerste image = persoon, rest = stijl). */
  styleReferenceDataUrls?: string[] | null;
  /** E55.7-bakeoff-hendel: gpt-image-kwaliteitstier. Productie laat dit weg
   *  (→ "high"); alleen de bakeoff-driver zet "medium" om de latency/kosten-
   *  arm te meten. Wordt het ooit de default, dan hier het vaste veld flippen. */
  gptQuality?: "high" | "medium";
  /** E55.7-bakeoff-hendel: timeout-override zodat de driver échte p50/p95
   *  kan meten voorbij het prod-budget (gpt-image-2 bleek >80s te kunnen).
   *  Productie laat dit weg (→ STYLIZE_TIMEOUT_MS). */
  timeoutMs?: number;
}): Promise<string> {
  const ref = input.model ?? defaultModelRef("stylize");
  const payload = stylizeInputFor(ref, input);
  const output = (await runWithRetry(
    "stylizeEdit",
    () => replicate.run(ref as `${string}/${string}`, { input: payload }),
    input.timeoutMs ?? STYLIZE_TIMEOUT_MS,
  )) as unknown;

  return extractUrl(output, "stylizeEdit");
}

function stylizeInputFor(
  ref: string,
  input: {
    imageDataUrl: string;
    prompt: string;
    width: number;
    height: number;
    styleReferenceDataUrls?: string[] | null;
    gptQuality?: "high" | "medium";
  },
): Record<string, unknown> {
  // Het portret eerst (dat is het te bewerken beeld), stijlreferenties daarna.
  // Alle vier armen nemen een image-array, dus extra beelden zijn een append;
  // de prompt vertelt het model welke rol elk beeld speelt (E54-rolclausule,
  // resp. CUSTOM_STYLE_TEMPLATE voor user-created effects).
  if (ref.startsWith("google/nano-banana")) {
    const images = [input.imageDataUrl, ...(input.styleReferenceDataUrls ?? [])];
    return {
      prompt: input.prompt,
      image_input: images,
      aspect_ratio: "match_input_image",
      output_format: "png",
    };
  }
  if (ref.startsWith("bytedance/seedream")) {
    // E32.1 face-bakeoff-arm. Seedream 4 = unified generate/edit; reference-
    // beelden gaan via `image_input` (zoals nano-banana), met
    // `aspect_ratio: "match_input_image"` zodat het kader niet herkadert.
    // Schema controleren vóór de eerste bakeoff-run (replicate.com/bytedance/
    // seedream-4); bij een veld-mismatch faalt de dev-only call zichtbaar.
    const images = [input.imageDataUrl, ...(input.styleReferenceDataUrls ?? [])];
    return {
      prompt: input.prompt,
      image_input: images,
      aspect_ratio: "match_input_image",
      size: "2K",
    };
  }
  if (ref.startsWith("black-forest-labs/flux-2")) {
    const images = [input.imageDataUrl, ...(input.styleReferenceDataUrls ?? [])];
    return {
      prompt: input.prompt,
      input_images: images,
      resolution: "match_input_image",
      aspect_ratio: "match_input_image",
      output_format: "png",
      // Zelfde reden als outpaintPortrait: lager weigert op onschuldige
      // portretten.
      safety_tolerance: 2,
    };
  }
  if (ref.startsWith("openai/gpt-image")) {
    const images = [input.imageDataUrl, ...(input.styleReferenceDataUrls ?? [])];
    const payload: Record<string, unknown> = {
      prompt: input.prompt,
      input_images: images,
      // Besluit Thierry 2026-08-03 (E55.7-bakeoff): MEDIUM als default —
      // visueel ≈ high op profielfoto-formaat (avatars worden klein getoond),
      // maar 65s p50 i.p.v. 169s en kosten ≈ nano ($0.047 vs $0.128).
      // `gptQuality` blijft de hendel voor bakeoffs/een latere premium-arm.
      quality: input.gptQuality ?? "medium",
      output_format: "png",
      moderation: "low",
      // gpt-image kent geen match_input_image; kies de dichtstbijzijnde uit
      // de ratio-set van dít model (2.0 kent er meer dan 1.5 — registry-
      // capability). Bij het E55.1-aspect-contract is de input al naar
      // precies zo'n ratio gepad, dus dit is dan een exacte hit.
      aspect_ratio: nearestFixedAspect(
        input.width,
        input.height,
        modelFixedAspects(ref) ?? GPT_IMAGE_ASPECTS,
      ).key,
    };
    // Alleen 1.5 kent de expliciete identity-hendel; 2.0 dropte de parameter
    // (schema 2026-08-02) en Replicate weigert onbekende input-velden.
    if (ref.startsWith("openai/gpt-image-1.5")) {
      payload.input_fidelity = "high";
    }
    return payload;
  }
  throw new Error(`stylizeEdit: no input adapter for model ref "${ref}"`);
}

const BACKGROUND_TIMEOUT_MS = 80_000;

/**
 * Text-to-background via neutral canvas + instruction-edit models
 * (E42). Caller supplies the composed prompt and a grey canvas data URL
 * at the target aspect ratio.
 */
export async function generateBackgroundImage(input: {
  prompt: string;
  imageDataUrl: string;
  width: number;
  height: number;
  model?: string | null;
}): Promise<string> {
  const ref = input.model ?? defaultModelRef("generate_background");
  const payload = stylizeInputFor(ref, {
    imageDataUrl: input.imageDataUrl,
    prompt: input.prompt,
    width: input.width,
    height: input.height,
  });
  const output = (await runWithRetry(
    "generateBackgroundImage",
    () => replicate.run(ref as `${string}/${string}`, { input: payload }),
    BACKGROUND_TIMEOUT_MS,
  )) as unknown;

  return extractUrl(output, "generateBackgroundImage");
}

/**
 * Replicate's SDK output is one of: a string URL, an array of URLs, or a
 * File-like object with a `.url()` method, depending on model + SDK
 * version. Normalise to a single URL string.
 */
function extractUrl(output: unknown, source: string): string {
  if (typeof output === "string") return output;
  if (Array.isArray(output)) {
    // gpt-image-1.5 levert een ARRAY van FileOutput-objecten (multi-image
    // models doen dat allemaal); pak het eerste element en val door naar
    // de object-tak hieronder.
    if (typeof output[0] === "string") return output[0];
    return extractUrl(output[0], source);
  }
  if (output && typeof output === "object" && "url" in output) {
    const fn = (output as { url: () => unknown }).url;
    // .url() geeft in nieuwere SDK-versies een URL-object terug — altijd
    // naar string dwingen.
    if (typeof fn === "function") return String(fn.call(output));
  }
  throw new Error(`Unexpected Replicate output shape from ${source}`);
}
