import Replicate from "replicate";

const replicate = new Replicate({ auth: process.env.REPLICATE_API_TOKEN! });

/**
 * Magic Cutout — runs a background-removal model on the input portrait.
 * Returns the URL of the resulting transparent-PNG. The caller downloads it
 * and re-encodes for the client.
 *
 * Model: `men1scus/birefnet` — BiRefNet (Bilateral Reference Network), the
 * academic gold-standard for portrait matting. Produces fine alpha at hair
 * boundaries that the cheaper alternatives (transparent-background,
 * tracer_b7, U2Net) can't match. ~$0.0017 per call.
 *
 * The version hash is pinned: it makes the call deterministic across model
 * updates AND avoids the `/v1/models/{slug}/predictions` 404 we hit before
 * (some Replicate models don't expose a default version for the
 * `replicate.run("slug")` shortcut). To upgrade: pick a new hash from
 * https://replicate.com/men1scus/birefnet/versions after smoke-testing.
 */
const MODEL_VERSION =
  "men1scus/birefnet:f74986db0355b58403ed20963af156525e2891ea3c2d499bfbfb2a28cd87c5d7";

export async function magicCutout(input: {
  imageDataUrl: string;
}): Promise<string> {
  const output = (await replicate.run(MODEL_VERSION, {
    input: {
      image: input.imageDataUrl,
      // 2048x2048 is the practical upper bound — BiRefNet runs at this on a
      // T4 in <10s. Larger inputs are bilinear-upscaled internally and don't
      // sharpen the matte further. The client already caps long-edge at the
      // canvas-friendly 2048 before sending.
      resolution: "2048x2048",
    },
  })) as unknown;

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
 * Replicate exposes the model under the unversioned slug; pin a hash from
 * https://replicate.com/black-forest-labs/flux-fill-pro/versions if a 404
 * appears (same fallback we use for BiRefNet).
 */
export async function outpaintPortrait(input: {
  imageDataUrl: string;
  maskDataUrl: string;
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

  const output = (await replicate.run("black-forest-labs/flux-fill-pro", {
    input: {
      image: input.imageDataUrl,
      mask: input.maskDataUrl,
      prompt,
      output_format: "png",
      // Max permitted with an input image. Lower values may refuse on
      // perfectly innocuous portraits.
      safety_tolerance: 2,
    },
  })) as unknown;

  return extractUrl(output, "outpaintPortrait");
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
