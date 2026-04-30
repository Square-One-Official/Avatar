import sharp from "sharp";

/**
 * Default outpainting padding ratios for Fill in Body. These are the
 * server-side fallback when the client doesn't request a specific amount.
 *
 * The client SHOULD pass exact pixel padding tailored to the user's
 * current scale & framing — that way generated body content lands
 * exactly inside the visible canvas at the user's preserved zoom rather
 * than extending off-canvas where the user can't see it.
 *
 * Padding is asymmetric on purpose:
 * - Bottom only (no top): keeps the head/eyes at the same y-coordinate
 *   within the canvas the model sees.
 * - Sides equal: handles circle-cropped sources where shoulders clip.
 */
export const DEFAULT_PAD_BOTTOM_RATIO = 0.5;
export const DEFAULT_PAD_SIDES_RATIO = 0.15;

/** Hard caps so a misbehaving client can't request a giant Replicate input. */
export const MAX_PAD_BOTTOM_RATIO = 1.5; // up to 150% of original height below
export const MAX_PAD_SIDES_RATIO = 0.6;  // up to 60% of original width per side
/** Floor so we always extend a little for circle crops / future re-alignment. */
export const MIN_PAD_BOTTOM_RATIO = 0.15;
export const MIN_PAD_SIDES_RATIO = 0.05;

export type OutpaintInputs = {
  imageDataUrl: string;
  maskDataUrl: string;
  originalWidth: number;
  originalHeight: number;
  paddedWidth: number;
  paddedHeight: number;
  padLeft: number;
  padTop: number;
};

export type PadRequest = {
  /** Pixels of padding below the original cutout. Undefined → use default ratio. */
  padBottomPx?: number;
  /** Pixels of padding on each side (left = right). Undefined → use default ratio. */
  padSidesPx?: number;
};

/**
 * Prepares the inputs for Flux Fill Pro outpainting:
 * 1. Flatten the alpha cutout onto white (Flux expects RGB).
 * 2. Extend the canvas down + sideways with white fill, by the requested
 *    pixel amount (or default ratio of the original cutout if unspecified).
 * 3. Build a black/white mask: black = keep original pixels, white = generate.
 *
 * Requested padding is clamped against floor + cap: 15-150% of original
 * height below, 5-60% of original width per side.
 *
 * Both images are returned as data URLs so they can be sent to Replicate
 * without intermediate hosting.
 */
export async function prepareOutpaintInputs(
  cutoutPng: Buffer,
  request: PadRequest = {},
): Promise<OutpaintInputs> {
  const meta = await sharp(cutoutPng).metadata();
  if (!meta.width || !meta.height) {
    throw new Error("Invalid cutout PNG: missing dimensions");
  }
  const originalWidth = meta.width;
  const originalHeight = meta.height;

  const requestedBottom = request.padBottomPx ?? originalHeight * DEFAULT_PAD_BOTTOM_RATIO;
  const requestedSides = request.padSidesPx ?? originalWidth * DEFAULT_PAD_SIDES_RATIO;

  const padBottom = clamp(
    Math.round(requestedBottom),
    Math.round(originalHeight * MIN_PAD_BOTTOM_RATIO),
    Math.round(originalHeight * MAX_PAD_BOTTOM_RATIO),
  );
  const padSides = clamp(
    Math.round(requestedSides),
    Math.round(originalWidth * MIN_PAD_SIDES_RATIO),
    Math.round(originalWidth * MAX_PAD_SIDES_RATIO),
  );
  const padLeft = padSides;
  const padRight = padSides;
  const padTop = 0;

  const paddedWidth = originalWidth + padLeft + padRight;
  const paddedHeight = originalHeight + padTop + padBottom;

  const white = { r: 255, g: 255, b: 255 };

  const paddedImage = await sharp(cutoutPng)
    .flatten({ background: white })
    .extend({ top: padTop, bottom: padBottom, left: padLeft, right: padRight, background: white })
    .png()
    .toBuffer();

  // Mask: white everywhere we want filled, black where the original cutout
  // pixels live. We start from a fully-white canvas and composite a black
  // rectangle covering the original-cutout region.
  const mask = await sharp({
    create: {
      width: paddedWidth,
      height: paddedHeight,
      channels: 3,
      background: white,
    },
  })
    .composite([
      {
        input: {
          create: {
            width: originalWidth,
            height: originalHeight,
            channels: 3,
            background: { r: 0, g: 0, b: 0 },
          },
        },
        top: padTop,
        left: padLeft,
      },
    ])
    .png()
    .toBuffer();

  return {
    imageDataUrl: `data:image/png;base64,${paddedImage.toString("base64")}`,
    maskDataUrl: `data:image/png;base64,${mask.toString("base64")}`,
    originalWidth,
    originalHeight,
    paddedWidth,
    paddedHeight,
    padLeft,
    padTop,
  };
}

function clamp(value: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, value));
}
