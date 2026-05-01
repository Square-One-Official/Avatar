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
 *   - Output canvas: 1024x1024 — large enough for FLUX inpaint to
 *     produce convincing skin/cloth detail, small enough to keep
 *     wall-clock under ~10s and stay well below Replicate's 1MP cap.
 */
const OUTPAINT_CANVAS = 1024;
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

  // Scale the trimmed cutout so its longer edge fits inside ~60% of
  // the canvas — leaves a comfortable margin on every side for the
  // model to extend into.
  const targetMax = Math.round(OUTPAINT_CANVAS * 0.6);
  const scale = Math.min(targetMax / bboxW, targetMax / bboxH, 1);
  const drawW = Math.max(1, Math.round(bboxW * scale));
  const drawH = Math.max(1, Math.round(bboxH * scale));

  const resized = await sharp(trimmed.data)
    .resize(drawW, drawH, { fit: "fill" })
    .png()
    .toBuffer();

  // Place the person centered horizontally, slightly above center
  // vertically (so the model adds chest/shoulders below, not weird
  // hair extensions above).
  const left = Math.round((OUTPAINT_CANVAS - drawW) / 2);
  const top = Math.round(OUTPAINT_CANVAS * 0.18);

  // Padded RGB: grey canvas with the cutout composited on top.
  // `flatten` after composite drops the alpha so the inpaint model
  // sees a normal RGB photo (most expect 3-channel input).
  const padded = await sharp({
    create: {
      width: OUTPAINT_CANVAS,
      height: OUTPAINT_CANVAS,
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
  const personAlpha = await sharp(resized)
    .extractChannel("alpha")
    .toBuffer();

  // Convert alpha (255 = person) into mask-keep (0 = person, 255 = bg).
  const inverted = await sharp(personAlpha, {
    raw: { width: drawW, height: drawH, channels: 1 },
  })
    .negate({ alpha: false })
    .png()
    .toBuffer();

  const mask = await sharp({
    create: {
      width: OUTPAINT_CANVAS,
      height: OUTPAINT_CANVAS,
      channels: 3,
      background: { r: 255, g: 255, b: 255 },
    },
  })
    .composite([{ input: inverted, left, top }])
    .blur(4)
    .png()
    .toBuffer();

  return { padded, mask };
}
