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
 * Reframe a portrait using Google Nano Banana, an instruction-based,
 * identity-preserving image editor. Takes the existing photo + a natural-
 * language reframe instruction; returns a regenerated portrait with the
 * SAME face/hair/clothing but new framing (full upper-body in our case).
 *
 * Why Nano Banana over Flux Fill Pro: generic inpainters fill masked
 * regions to be visually consistent with their surroundings; given a
 * person on white background they extend the white background, not the
 * body. Nano Banana's model card specifically calls out identity
 * preservation across regenerations — the right tool for "extend the
 * person, keep the face exactly."
 *
 * Replicate's `replicate.run("slug")` shortcut resolves to the latest
 * version. If we hit a 404 on the unversioned slug, pin a hash from
 * https://replicate.com/google/nano-banana/versions the same way
 * `MODEL_VERSION` does for BiRefNet.
 *
 * Returns the URL of the result image (RGB, no alpha — caller must
 * re-extract the matte via `magicCutout` before handing it to the client).
 */
export const FILL_BODY_INSTRUCTION =
  "Reframe this image as a head-and-shoulders studio portrait. Show the " +
  "person from the top of the head down to the upper chest only — a " +
  "classic LinkedIn / passport-style framing. Keep the exact same face, " +
  "skin tone, hair, and clothing. Add only the missing shoulders and " +
  "upper-chest area. DO NOT add arms below the shoulders, hands, waist, " +
  "belt, trousers, or any lower body. Centred composition. Studio " +
  "portrait, neutral grey background, soft photographic lighting, sharp " +
  "focus.";

export async function editPortrait(input: {
  imageDataUrl: string;
  prompt?: string;
}): Promise<string> {
  const output = (await replicate.run("google/nano-banana", {
    input: {
      // `image_input` is an array on Replicate's nano-banana — verified
      // against https://replicate.com/google/nano-banana/llms.txt
      // (single-element array for single-image edits).
      image_input: [input.imageDataUrl],
      prompt: input.prompt ?? FILL_BODY_INSTRUCTION,
      output_format: "png",
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
