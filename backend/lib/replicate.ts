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
 * Reframe a portrait using Black Forest Labs' Flux Kontext Pro — an
 * instruction-based photo editor designed for "edit this single image"
 * rather than multi-image fusion.
 *
 * Why Kontext Pro over Nano Banana: Nano Banana's signature is multi-
 * image fusion, and even with a single-image input + an explicit
 * "one person only" prompt it kept producing collages with hallucinated
 * second subjects and (on the last test) an outright identity swap.
 * Kontext Pro is purpose-built for instruction edits with character
 * consistency, and Replicate's benchmark called out its photographic
 * skin/cloth quality as best-in-class.
 *
 * Replicate's `replicate.run("slug")` shortcut resolves to the latest
 * version automatically. If we hit a 404 on the unversioned slug, pin
 * a hash from https://replicate.com/black-forest-labs/flux-kontext-pro/versions
 * the same way `MODEL_VERSION` does for BiRefNet.
 *
 * Returns the URL of the result image (RGB, no alpha — caller must
 * re-extract the matte via `magicCutout` before handing it to the client).
 */
// Kept short — long, multi-clause prompts gave Nano Banana surface area
// to interpret each clause as a separate composition element. Same risk
// applies less to Kontext Pro (it doesn't do fusion), but minimal direct
// instruction is good practice either way.
export const FILL_BODY_INSTRUCTION =
  "Reframe as a professional headshot. Keep the exact same face, hair, " +
  "skin, and shirt. Plain neutral grey background. One person only.";

export async function editPortrait(input: {
  imageDataUrl: string;
  prompt?: string;
}): Promise<string> {
  const output = (await replicate.run("black-forest-labs/flux-kontext-pro", {
    input: {
      // Single-string `input_image` (not an array). Schema verified from
      // https://replicate.com/black-forest-labs/flux-kontext-pro/llms.txt.
      input_image: input.imageDataUrl,
      prompt: input.prompt ?? FILL_BODY_INSTRUCTION,
      // Preserve source dimensions so BiRefNet downstream gets the same
      // aspect ratio it would have for any other cutout.
      aspect_ratio: "match_input_image",
      output_format: "png",
      // Max permitted with an input image. Lower values may refuse on
      // perfectly innocuous portraits.
      safety_tolerance: 2,
    },
  })) as unknown;

  return extractUrl(output, "editPortrait");
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
