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

  if (typeof output === "string") return output;
  if (Array.isArray(output) && typeof output[0] === "string") return output[0];
  if (output && typeof output === "object" && "url" in output) {
    const fn = (output as { url: () => string }).url;
    if (typeof fn === "function") return fn();
  }
  throw new Error("Unexpected Replicate output shape from magicCutout");
}
