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
 * Analyse a portrait via Google's Gemini 2.5 Flash and report whether
 * the photo is already a complete head-and-upper-chest portrait or has
 * body parts clipped at its edges. Used as the first step of Fill in
 * Body so we can (a) skip the expensive edit when nothing is wrong, and
 * (b) feed Kontext Pro a SPECIFIC description of what to extend instead
 * of a generic "outpaint the body" prompt that produces over-generation.
 *
 * Cost: ~$0.001 per call, ~3s. Cheap enough to run on every Fill in
 * Body, since the no-op path saves the ~$0.04 Kontext call entirely.
 */
export type PortraitAnalysis = {
  complete: boolean;
  missing: string;
};

export async function analyzePortrait(input: {
  imageDataUrl: string;
}): Promise<PortraitAnalysis> {
  const prompt =
    "You are analysing a portrait of one person on a plain grey background. " +
    "The grey is a placeholder backdrop — focus only on the person's silhouette " +
    "and decide whether the photo is a complete head-and-upper-chest portrait " +
    "or whether body parts are CLIPPED at the photo's edges.\n\n" +
    "Clipped means: the silhouette runs into one of the photo's edges and stops " +
    "abruptly, as if the camera frame cut the person off. Examples of clipped: " +
    "right arm cut off at the right edge, top of hair cut at the top edge, " +
    "elbow visible but forearm and hand clipped at the side.\n\n" +
    "NOT clipped (treat as complete): a normal chest-up portrait where the " +
    "shoulders sit comfortably inside the frame and the chest fades naturally " +
    "below the visible torso. A standard headshot is COMPLETE even if the " +
    "person stops at the chest — that is intentional framing, not clipping.\n\n" +
    "Reply with EXACTLY this JSON object on a single line, nothing else:\n" +
    '{"complete": true|false, "missing": "<short description of clipped parts, or empty string if complete>"}\n\n' +
    "Examples:\n" +
    '{"complete": true, "missing": ""}\n' +
    '{"complete": false, "missing": "right arm clipped at right edge below the elbow"}\n' +
    '{"complete": false, "missing": "top of the hair clipped at the top edge"}';

  const output = (await replicate.run("google/gemini-2.5-flash", {
    input: {
      prompt,
      images: [input.imageDataUrl],
      // Determinism over creativity for an analysis task.
      temperature: 0.1,
      max_output_tokens: 256,
      dynamic_thinking: false,
    },
  })) as unknown;

  // Gemini on Replicate returns an array of strings that concatenate into the
  // full text response. Normalise.
  const raw = Array.isArray(output) ? output.join("") : String(output ?? "");
  return parseAnalysis(raw);
}

/**
 * Pull the JSON object out of Gemini's raw text. We prompted for "exactly
 * this JSON" but VLMs often wrap it in prose or markdown fences. Be lenient.
 * Returns a sentinel { complete: false, missing: "" } on parse failure so the
 * caller can fall back to a generic edit prompt rather than failing the user.
 */
function parseAnalysis(raw: string): PortraitAnalysis {
  const match = raw.match(/\{[\s\S]*?\}/);
  if (!match) return { complete: false, missing: "" };
  try {
    const obj = JSON.parse(match[0]) as { complete?: unknown; missing?: unknown };
    return {
      complete: obj.complete === true,
      missing: typeof obj.missing === "string" ? obj.missing.trim() : "",
    };
  } catch {
    return { complete: false, missing: "" };
  }
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
/**
 * Build a Kontext Pro instruction that names the SPECIFIC body parts
 * Gemini said are clipped, then layers the project's hard constraints
 * (identity, framing, single subject) on top. Naming what to extend
 * was the missing piece — a generic "extend the body" prompt produced
 * over-generation (full waist + arms + belt) because the model had to
 * guess at the user's intent.
 */
export function buildFillBodyInstruction(missing: string): string {
  const clean = missing.trim();
  // If Gemini didn't (or couldn't) describe what's missing, fall back to a
  // minimal extension instruction. Better than a no-op since the user
  // explicitly clicked Fill in Body.
  const target = clean.length > 0
    ? `Extend only the missing parts of the person: ${clean}.`
    : "Extend the missing shoulders and upper chest of the person.";
  return [
    target,
    "Do not change the face, hair, skin, or clothing.",
    "Keep the existing pose. One person only.",
    "Frame as a head-and-upper-chest portrait on a plain neutral grey background.",
  ].join(" ");
}

export async function editPortrait(input: {
  imageDataUrl: string;
  missing: string;
}): Promise<string> {
  const output = (await replicate.run("black-forest-labs/flux-kontext-pro", {
    input: {
      // Single-string `input_image` (not an array). Schema verified from
      // https://replicate.com/black-forest-labs/flux-kontext-pro/llms.txt.
      input_image: input.imageDataUrl,
      prompt: buildFillBodyInstruction(input.missing),
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
