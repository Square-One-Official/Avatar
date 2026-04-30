import sharp from "sharp";

/**
 * Outpainting padding ratios for Fill in Body.
 *
 * Padding is asymmetric on purpose:
 * - Bottom only (no top): keeps the head/eyes at the SAME y-coordinate within
 *   the canvas the model sees, so the user's manual eye anchoring is easier
 *   to preserve client-side.
 * - Sides equal: handles circle-cropped sources where shoulders are clipped.
 *
 * Tuned for typical portrait crops. Push higher if shoulders still clip;
 * push lower to reduce Replicate spend per call.
 */
export const PAD_BOTTOM_RATIO = 0.6;
export const PAD_SIDES_RATIO = 0.25;

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

/**
 * Prepares the inputs for Flux Fill Pro outpainting:
 * 1. Flatten the alpha cutout onto white (Flux expects RGB).
 * 2. Extend the canvas down + sideways with white fill.
 * 3. Build a black/white mask: black = keep original pixels, white = generate.
 *
 * Both images are returned as data URLs so they can be sent to Replicate
 * without intermediate hosting.
 */
export async function prepareOutpaintInputs(
  cutoutPng: Buffer,
): Promise<OutpaintInputs> {
  const meta = await sharp(cutoutPng).metadata();
  if (!meta.width || !meta.height) {
    throw new Error("Invalid cutout PNG: missing dimensions");
  }
  const originalWidth = meta.width;
  const originalHeight = meta.height;

  const padBottom = Math.round(originalHeight * PAD_BOTTOM_RATIO);
  const padSides = Math.round(originalWidth * PAD_SIDES_RATIO);
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
