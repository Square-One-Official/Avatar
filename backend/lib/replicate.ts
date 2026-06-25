import Replicate from "replicate";
import { defaultModelRef } from "./models.js";

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN! });

/**
 * Hard timeout for any single `replicate.run()` call (audit MEDIUM #17).
 * The SDK has no built-in client-side timeout; a hung Replicate prediction
 * would otherwise let the Vercel function run to its 60s `maxDuration`,
 * costing the user a full timeout instead of a clean 504.
 *
 * 50s leaves ~10s of headroom under Vercel's default function ceiling so
 * the handler can still finalise (free-trial counter, response write)
 * after we surface the timeout.
 */
const REPLICATE_TIMEOUT_MS = 50_000;

export class ReplicateTimeoutError extends Error {
  constructor(public readonly model: string) {
    super(`replicate.run(${model}) timed out after ${REPLICATE_TIMEOUT_MS}ms`);
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
        timer = setTimeout(() => reject(new ReplicateTimeoutError(model)), timeoutMs);
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
 */
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
  const output = (await runWithRetry(
    "upscale",
    () => replicate.run((input.model ?? defaultModelRef("upscale")) as `${string}/${string}`, {
      input: {
        image: input.imageDataUrl,
        scale: 2,
        face_enhance: false,
      },
    }),
  )) as unknown;

  return extractUrl(output, "upscale");
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
 * Ruimere timeout dan de 50s-default: gpt-image op hoge kwaliteit zit
 * geregeld boven de 50s. De endpoint-maxDuration (90s, vercel.json) houdt
 * 10s marge voor afronden van de response.
 */
const STYLIZE_TIMEOUT_MS = 80_000;

export async function stylizeEdit(input: {
  imageDataUrl: string;
  prompt: string;
  /** Breedte/hoogte van de input, voor armen zonder match_input_image. */
  width: number;
  height: number;
  model?: string | null;
  /**
   * E34: optionele STIJL-REFERENTIE (user-created custom effect). Gaat als
   * tweede beeld mee in de model-image-array; het portret (`imageDataUrl`)
   * blijft het eerste/te-bewerken beeld. De prompt verheldert de rol (zie
   * stylize.ts CUSTOM_STYLE_TEMPLATE). nil = gewone één-beeld-stylize.
   */
  referenceDataUrl?: string | null;
}): Promise<string> {
  const ref = input.model ?? defaultModelRef("stylize");
  const payload = stylizeInputFor(ref, input);
  const output = (await runWithRetry(
    "stylizeEdit",
    () => replicate.run(ref as `${string}/${string}`, { input: payload }),
    STYLIZE_TIMEOUT_MS,
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
    referenceDataUrl?: string | null;
  },
): Record<string, unknown> {
  // E34: het portret eerst (te bewerken), de optionele stijlreferentie tweede.
  // Alle vier armen nemen een image-array, dus een tweede beeld is een append;
  // de prompt (CUSTOM_STYLE_TEMPLATE) vertelt het model welke rol elk speelt.
  const images = input.referenceDataUrl
    ? [input.imageDataUrl, input.referenceDataUrl]
    : [input.imageDataUrl];
  if (ref.startsWith("google/nano-banana")) {
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
    return {
      prompt: input.prompt,
      image_input: images,
      aspect_ratio: "match_input_image",
      size: "2K",
    };
  }
  if (ref.startsWith("black-forest-labs/flux-2")) {
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
    return {
      prompt: input.prompt,
      input_images: images,
      // Identity-behoud staat of valt met input_fidelity=high; quality=high
      // is de eerlijke vergelijking met de andere pro-armen (en de reden
      // voor STYLIZE_TIMEOUT_MS).
      input_fidelity: "high",
      quality: "high",
      output_format: "png",
      moderation: "low",
      // gpt-image kent geen match_input_image; kies de dichtstbijzijnde
      // van de drie ondersteunde ratio's.
      aspect_ratio: nearestGptAspect(input.width, input.height),
    };
  }
  throw new Error(`stylizeEdit: no input adapter for model ref "${ref}"`);
}

function nearestGptAspect(width: number, height: number): "1:1" | "3:2" | "2:3" {
  if (width <= 0 || height <= 0) return "1:1";
  const ratio = width / height;
  const options: Array<["1:1" | "3:2" | "2:3", number]> = [
    ["1:1", 1],
    ["3:2", 1.5],
    ["2:3", 2 / 3],
  ];
  options.sort((a, b) => Math.abs(a[1] - ratio) - Math.abs(b[1] - ratio));
  return options[0][0];
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
