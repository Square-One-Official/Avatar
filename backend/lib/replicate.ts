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

async function runWithTimeout<T>(model: string, p: Promise<T>): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      p,
      new Promise<T>((_, reject) => {
        timer = setTimeout(() => reject(new ReplicateTimeoutError(model)), REPLICATE_TIMEOUT_MS);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
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
  const output = (await runWithTimeout(
    "magicCutout",
    replicate.run((input.model ?? defaultModelRef("cutout")) as `${string}/${string}`, {
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

  const output = (await runWithTimeout(
    "outpaintPortrait",
    replicate.run((input.model ?? defaultModelRef("fill_body")) as `${string}/${string}`, {
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
  const output = (await runWithTimeout(
    "colorize",
    replicate.run((input.model ?? defaultModelRef("colorize")) as `${string}/${string}`, {
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
 * Replicate's SDK output is one of: a string URL, an array of URLs, or a
 * File-like object with a `.url()` method, depending on model + SDK
 * version. Normalise to a single URL string.
 */
function extractUrl(output: unknown, source: string): string {
  if (typeof output === "string") return output;
  if (Array.isArray(output) && typeof output[0] === "string") return output[0];
  if (output && typeof output === "object" && "url" in output) {
    const fn = (output as { url: () => string }).url;
    if (typeof fn === "function") return fn();
  }
  throw new Error(`Unexpected Replicate output shape from ${source}`);
}
