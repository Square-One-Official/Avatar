import sharp from "sharp";

/**
 * Flatten a transparent-background cutout PNG onto a neutral grey
 * background so identity-preserving instruction editors (Nano Banana,
 * Flux Kontext, etc.) get a normal RGB photo to work with.
 *
 * Why grey, not white: white-on-white-shirt collapses contrast at the
 * shirt boundary and gives the model no signal about where the cutout
 * person ends. A mid-grey reads as a studio backdrop and lets the model
 * cleanly reframe the subject.
 */
export async function flattenOnGrey(cutoutPng: Buffer): Promise<Buffer> {
  return sharp(cutoutPng)
    .flatten({ background: { r: 200, g: 200, b: 200 } })
    .png()
    .toBuffer();
}

/**
 * Build outpainting inputs from a transparent-background cutout PNG.
 *
 * Returns a (padded, mask) pair sized identically:
 *   - `padded`: the original RGBA cutout composited onto a mid-grey
 *     canvas. The original pixels are preserved bit-for-bit; only the
 *     padded margins are grey. Identity is therefore guaranteed —
 *     downstream the inpaint model only fills the masked region.
 *   - `mask`: white where the model should generate (the padded
 *     margin), black where it must keep the input untouched (the
 *     person's existing silhouette). Feathered slightly so the seam
 *     between original and generated pixels blends.
 *
 * Sizing recipe:
 *   - Detect the alpha bbox of the cutout.
 *   - Resize so the bbox occupies ~60% of the target canvas height,
 *     centered horizontally, biased toward the upper third vertically
 *     (head-and-upper-chest framing leaves room *below* the torso).
 *   - Output canvas: 768x1024 (3:4 portrait). Square canvases gave the
 *     model so much horizontal margin to fill that it hallucinated
 *     props (a microphone-stick in one early test). Portrait shape
 *     constrains the side margins to ~10–15% each, leaving the model
 *     no room to invent a scene.
 */
const CANVAS_W = 768;
const CANVAS_H = 1024;
const GREY = { r: 200, g: 200, b: 200 };

export async function padForOutpaint(
  cutoutPng: Buffer
): Promise<{ padded: Buffer; mask: Buffer }> {
  const src = sharp(cutoutPng).ensureAlpha();
  const meta = await src.metadata();
  if (!meta.width || !meta.height) {
    throw new Error("padForOutpaint: source has no dimensions");
  }

  // Find the tight alpha bbox so we know where the actual person is.
  // `trim()` on alpha returns the cropped image plus its offset within
  // the original; we use that offset to compute scale + placement.
  const trimmed = await sharp(cutoutPng)
    .ensureAlpha()
    .trim({ background: { r: 0, g: 0, b: 0, alpha: 0 }, threshold: 1 })
    .toBuffer({ resolveWithObject: true });
  const bboxW = trimmed.info.width;
  const bboxH = trimmed.info.height;

  // Scale the trimmed cutout so the person fills ~70% of the canvas
  // height while staying within ~85% of the canvas width. Tall canvas
  // + tall person = the only fillable area is below-chest, which is
  // exactly what we want extended.
  const heightTarget = CANVAS_H * 0.7;
  const widthCap = CANVAS_W * 0.85;
  const scale = Math.min(heightTarget / bboxH, widthCap / bboxW, 1);
  const drawW = Math.max(1, Math.round(bboxW * scale));
  const drawH = Math.max(1, Math.round(bboxH * scale));

  const resized = await sharp(trimmed.data)
    .resize(drawW, drawH, { fit: "fill" })
    .png()
    .toBuffer();

  // Place the person centered horizontally, with the head near the
  // top (small ~6% top margin) so the model fills downward into the
  // chest/torso region rather than upward into hair extensions.
  const left = Math.round((CANVAS_W - drawW) / 2);
  const top = Math.round(CANVAS_H * 0.06);

  // Padded RGB: grey canvas with the cutout composited on top.
  // `flatten` after composite drops the alpha so the inpaint model
  // sees a normal RGB photo (most expect 3-channel input).
  const padded = await sharp({
    create: {
      width: CANVAS_W,
      height: CANVAS_H,
      channels: 4,
      background: { ...GREY, alpha: 1 },
    },
  })
    .composite([{ input: resized, left, top }])
    .flatten({ background: GREY })
    .png()
    .toBuffer();

  // Mask: white everywhere by default (= "fill"), black where the
  // person's alpha is opaque (= "keep"). Slight blur feathers the
  // boundary so the inpaint model blends instead of leaving a hard
  // line at the silhouette edge.
  //
  // Pull the person's alpha out as raw bytes (1 byte/px, 0=transparent,
  // 255=opaque). Inverting gives us a single-channel mask where the
  // person is black and the background is white — exactly what FLUX
  // Fill wants.
  const alphaRaw = await sharp(resized)
    .extractChannel("alpha")
    .raw()
    .toBuffer({ resolveWithObject: true });

  const invertedBytes = Buffer.alloc(alphaRaw.data.length);
  for (let i = 0; i < alphaRaw.data.length; i++) {
    invertedBytes[i] = 255 - alphaRaw.data[i]!;
  }

  const personMaskPng = await sharp(invertedBytes, {
    raw: {
      width: alphaRaw.info.width,
      height: alphaRaw.info.height,
      channels: 1,
    },
  })
    .png()
    .toBuffer();

  const mask = await sharp({
    create: {
      width: CANVAS_W,
      height: CANVAS_H,
      channels: 3,
      background: { r: 255, g: 255, b: 255 },
    },
  })
    .composite([{ input: personMaskPng, left, top }])
    .blur(4)
    .png()
    .toBuffer();

  return { padded, mask };
}
