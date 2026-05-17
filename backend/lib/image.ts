import sharp from "sharp";

/**
 * Post-decode payload cap for `/v1/colorize` and `/v1/fill-body`. The
 * Vercel `bodyParser.sizeLimit` on those endpoints is 15 MB, which is
 * the *base64-encoded* request size. After decoding, the raw image
 * Buffer is ~75% of that — so this 12 MB cap on the decoded bytes is
 * always reached first.
 *
 * Audit MEDIUM #16: shared here so the two endpoints can't drift apart
 * and a future endpoint reuses the same limit. Bumping the underlying
 * `bodyParser.sizeLimit` is meaningless unless this constant moves too.
 */
export const MAX_DECODED_IMAGE_BYTES = 12 * 1024 * 1024;

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
 * Re-attach the alpha channel from `originalRgba` onto `colorizedRgb`,
 * resizing the alpha to match if dimensions disagree (DeOldify and other
 * RGB models occasionally return a slightly different size due to internal
 * resampling). Output is a PNG with the original silhouette preserved
 * exactly. Used by /v1/colorize so the cutout's transparent background
 * survives the round-trip through an RGB-only colorization model.
 */
export async function reapplyAlpha(
  colorizedRgb: Buffer,
  originalRgba: Buffer,
): Promise<Buffer> {
  const colorMeta = await sharp(colorizedRgb).metadata();
  const w = colorMeta.width;
  const h = colorMeta.height;
  if (!w || !h) {
    throw new Error("reapplyAlpha: colorized image has no dimensions");
  }
  const alpha = await sharp(originalRgba)
    .ensureAlpha()
    .extractChannel("alpha")
    .resize(w, h, { fit: "fill" })
    .toBuffer();
  return sharp(colorizedRgb)
    .removeAlpha()
    .joinChannel(alpha)
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

/**
 * Optional face bbox in normalised input-image coords (0..1, top-left
 * origin). When provided, the outpaint mask hard-locks that region (plus a
 * generous margin for hair/ears/neck) as never-paint. Source: Apple Vision
 * face detection on the client, before upload.
 */
export interface FaceBox {
  x: number;
  y: number;
  width: number;
  height: number;
}

export async function padForOutpaint(
  cutoutPng: Buffer,
  options?: { face?: FaceBox }
): Promise<{ padded: Buffer; mask: Buffer }> {
  const src = sharp(cutoutPng).ensureAlpha();
  const meta = await src.metadata();
  if (!meta.width || !meta.height) {
    throw new Error("padForOutpaint: source has no dimensions");
  }

  // Find the tight alpha bbox so we know where the actual person is.
  // `trim()` on alpha returns the cropped image plus its offset within
  // the original; we use that offset to compute scale + placement, and
  // also to project the (original-image) face bbox into canvas coords.
  const trimmed = await sharp(cutoutPng)
    .ensureAlpha()
    .trim({ background: { r: 0, g: 0, b: 0, alpha: 0 }, threshold: 1 })
    .toBuffer({ resolveWithObject: true });
  const bboxW = trimmed.info.width;
  const bboxH = trimmed.info.height;
  // sharp returns trim offsets as negative numbers — the amount removed
  // from each side. Negate to get the bbox origin within the original
  // image (in pixels, top-left).
  const bboxOriginX = -(trimmed.info.trimOffsetLeft ?? 0);
  const bboxOriginY = -(trimmed.info.trimOffsetTop ?? 0);

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

  const featheredMask = await sharp({
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

  // Hard face guard: a rectangle forced black (= preserve) on the mask,
  // regardless of alpha. The rule is absolute — Fill in Body must NEVER
  // modify the face, even when alpha gaps exist there (cutout glitch,
  // half-missing chin, hair holes). FLUX Fill cannot paint into a
  // black-mask region. Two strategies, in order of preference:
  //   1. Client-detected face bbox (Apple Vision), projected through
  //      the trim → resize → placement pipeline into canvas pixels and
  //      expanded to cover hair/ears/neck. Reliable for any framing.
  //   2. Fallback heuristic: the top 55% of the person bbox. Used when
  //      the client couldn't detect a face (rare with portrait input).
  // The unblurred rectangle also overrides the 4px feather along the
  // silhouette in the face zone — feather still applies below.
  const guard = computeFaceGuardRect({
    face: options?.face,
    meta: { width: meta.width, height: meta.height },
    bboxOriginX,
    bboxOriginY,
    scale,
    drawW,
    drawH,
    left,
    top,
  });
  const faceGuard = await sharp({
    create: {
      width: guard.width,
      height: guard.height,
      channels: 3,
      background: { r: 0, g: 0, b: 0 },
    },
  })
    .png()
    .toBuffer();

  const mask = await sharp(featheredMask)
    .composite([{ input: faceGuard, left: guard.left, top: guard.top }])
    .png()
    .toBuffer();

  return { padded, mask };
}

/**
 * Compute the never-paint rectangle (in canvas pixels) that locks the
 * face region of the outpaint mask. When a client-detected face bbox is
 * available we project it through the same trim → resize → placement
 * transform that produced the padded canvas, then expand by face-relative
 * margins to cover hair (top), ears (sides), and a slice of neck (bottom).
 * The bottom margin is intentionally modest so Fill in Body can still
 * extend the chest/torso below the neck. When no face bbox is available
 * we fall back to the top 55% of the person bbox — a heuristic that holds
 * for the head-and-shoulders framing the app produces.
 */
function computeFaceGuardRect(args: {
  face?: FaceBox;
  meta: { width: number; height: number };
  bboxOriginX: number;
  bboxOriginY: number;
  scale: number;
  drawW: number;
  drawH: number;
  left: number;
  top: number;
}): { left: number; top: number; width: number; height: number } {
  const { face, meta, bboxOriginX, bboxOriginY, scale, drawW, drawH, left, top } = args;

  if (face) {
    // Original-image pixels.
    const fxOrig = face.x * meta.width;
    const fyOrig = face.y * meta.height;
    const fwOrig = face.width * meta.width;
    const fhOrig = face.height * meta.height;

    // Trimmed-bbox pixels.
    const fxTrim = fxOrig - bboxOriginX;
    const fyTrim = fyOrig - bboxOriginY;

    // Canvas pixels (trimmed → resized → placed).
    const fxCanvas = left + fxTrim * scale;
    const fyCanvas = top + fyTrim * scale;
    const fwCanvas = fwOrig * scale;
    const fhCanvas = fhOrig * scale;

    // Margins relative to face dimensions: hair generously above, ears
    // on the sides, a small slice of neck below. Numbers tuned for the
    // typical Vision face bbox (eyebrows-to-chin, temple-to-temple).
    const padTop = fhCanvas * 0.9;
    const padBottom = fhCanvas * 0.35;
    const padSides = fwCanvas * 0.55;

    const guardLeft = Math.max(0, Math.round(fxCanvas - padSides));
    const guardTop = Math.max(0, Math.round(fyCanvas - padTop));
    const guardRight = Math.min(CANVAS_W, Math.round(fxCanvas + fwCanvas + padSides));
    const guardBottom = Math.min(CANVAS_H, Math.round(fyCanvas + fhCanvas + padBottom));

    const w = Math.max(1, guardRight - guardLeft);
    const h = Math.max(1, guardBottom - guardTop);
    return { left: guardLeft, top: guardTop, width: w, height: h };
  }

  // Heuristic fallback: top 55% of the person bbox.
  const FACE_GUARD_RATIO = 0.55;
  return {
    left,
    top,
    width: drawW,
    height: Math.max(1, Math.round(drawH * FACE_GUARD_RATIO)),
  };
}
