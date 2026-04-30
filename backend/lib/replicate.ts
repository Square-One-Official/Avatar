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
 * Outpaint a portrait using Flux Fill Pro. The caller supplies a padded
 * RGB image and a black/white mask (black = keep, white = generate).
 *
 * Model: `black-forest-labs/flux-fill-pro`, currently SOTA for inpaint /
 * outpaint of photographic content. Replicate's `replicate.run("slug")`
 * shortcut resolves to the latest version automatically; if Replicate
 * starts returning 404s for the unversioned slug, pin a version hash here
 * the same way `MODEL_VERSION` does for BiRefNet.
 *
 * Returns the URL of the result image (RGB, no alpha — caller must
 * re-extract the matte before handing the result to the client).
 */
export const FILL_BODY_PROMPT =
  "natural continuation of the person's shoulders, torso and clothing; " +
  "matching skin tone and lighting; photograph, photorealistic, same outfit";

export async function outpaintBody(input: {
  imageDataUrl: string;
  maskDataUrl: string;
  prompt?: string;
}): Promise<string> {
  const output = (await replicate.run("black-forest-labs/flux-fill-pro", {
    input: {
      image: input.imageDataUrl,
      mask: input.maskDataUrl,
      prompt: input.prompt ?? FILL_BODY_PROMPT,
      // Tuned for body outpainting on portrait crops; revisit after
      // empirical sampling.
      guidance: 60,
      num_inference_steps: 50,
      safety_tolerance: 2,
      output_format: "png",
    },
  })) as unknown;

  return extractUrl(output, "outpaintBody");
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
