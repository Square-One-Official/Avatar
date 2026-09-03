import assert from "node:assert/strict";
import test from "node:test";
import sharp from "sharp";
import {
  computeMinimalBodyFillGeometry,
  prepareMinimalBodyFill,
  restoreMinimalBodyFillSubject,
} from "../lib/image.js";

const W = 100;
const H = 100;

function alphaWithRect(x0: number, y0: number, x1: number, y1: number): Uint8Array {
  const alpha = new Uint8Array(W * H);
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) alpha[y * W + x] = 255;
  }
  return alpha;
}

async function pngFromAlpha(alpha: Uint8Array): Promise<Buffer> {
  const rgba = Buffer.alloc(W * H * 4);
  for (let i = 0; i < alpha.length; i++) {
    rgba[i * 4] = 180;
    rgba[i * 4 + 1] = 40;
    rgba[i * 4 + 2] = 20;
    rgba[i * 4 + 3] = alpha[i]!;
  }
  return sharp(rgba, { raw: { width: W, height: H, channels: 4 } }).png().toBuffer();
}

const FW = 200;
const FH = 200;

/**
 * Realistic, antialiased subject: elliptical head + rounded torso in a
 * 200×200 canvas (large enough that antialiased curves stay clearly rounder
 * than a crop line), nowhere touching the canvas. Crops are applied by
 * extracting a window and (optionally) re-extending it with a transparent
 * gutter, so the same silhouette can be cut at the canvas edge or inside it.
 */
async function subjectPng(crop?: {
  left?: number;
  right?: number;
  bottom?: number;
  gutter?: { left?: number; right?: number; bottom?: number };
  hairSpike?: boolean;
}): Promise<Buffer> {
  const svg = `
    <svg width="${FW}" height="${FH}" xmlns="http://www.w3.org/2000/svg">
      <ellipse cx="100" cy="52" rx="30" ry="38" fill="#b4784b"/>
      <ellipse cx="100" cy="148" rx="64" ry="44" fill="#315b88"/>
      ${crop?.hairSpike ? '<rect x="0" y="28" width="80" height="16" fill="#5a3a22"/>' : ""}
    </svg>`;
  let image = sharp({
    create: { width: FW, height: FH, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
  }).composite([{ input: Buffer.from(svg) }]).png();
  if (crop && (crop.left !== undefined || crop.right !== undefined || crop.bottom !== undefined)) {
    const left = crop.left ?? 0;
    const right = crop.right ?? FW;
    const bottom = crop.bottom ?? FH;
    image = sharp(await image.toBuffer())
      .extract({ left, top: 0, width: right - left, height: bottom })
      .png();
    if (crop.gutter) {
      image = sharp(await image.toBuffer())
        .extend({
          left: crop.gutter.left ?? 0,
          right: crop.gutter.right ?? 0,
          bottom: crop.gutter.bottom ?? 0,
          background: { r: 0, g: 0, b: 0, alpha: 0 },
        })
        .png();
    }
  }
  return image.toBuffer();
}

async function alphaOf(png: Buffer): Promise<{ alpha: Uint8Array; width: number; height: number }> {
  const raw = await sharp(png).ensureAlpha().extractChannel("alpha").raw().toBuffer({
    resolveWithObject: true,
  });
  return { alpha: new Uint8Array(raw.data), width: raw.info.width, height: raw.info.height };
}

async function geometryOf(png: Buffer) {
  const { alpha, width, height } = await alphaOf(png);
  return computeMinimalBodyFillGeometry(alpha, width, height);
}

test("rounded central subject is a non-billable no-op", async () => {
  const png = await subjectPng();
  const preparation = await prepareMinimalBodyFill(png);
  assert.equal(preparation.shouldFill, false);
  if (preparation.shouldFill) return;
  assert.deepEqual(preparation.edges, { left: false, right: false, bottom: false });
  assert.equal(preparation.cutout.compare(png), 0);
});

test("detects a right-edge body crop at the canvas edge", async () => {
  const geometry = await geometryOf(await subjectPng({ right: 140 }));
  assert.equal(geometry.shouldFill, true);
  assert.deepEqual(geometry.edges, { left: false, right: true, bottom: false });
  assert.equal(geometry.cropRightX, 139);
  assert.equal(geometry.rightPadding, geometry.rightStrip);
  assert.equal(geometry.leftPadding, 0);
  assert.equal(geometry.bottomPadding, 0);
});

test("a transparent gutter does not hide a crop line (E56.2)", async () => {
  // Same cut at x=69, but the canvas keeps 30 px of empty margin — the
  // situation after a previous Fill in body that painted nothing there.
  const geometry = await geometryOf(await subjectPng({ right: 140, gutter: { right: 60 } }));
  assert.equal(geometry.shouldFill, true);
  assert.deepEqual(geometry.edges, { left: false, right: true, bottom: false });
  assert.equal(geometry.cropRightX, 139);
  assert.equal(geometry.rightPadding, 0, "existing margin already holds the strip");

  const small = await geometryOf(await subjectPng({ right: 140, gutter: { right: 10 } }));
  assert.equal(small.rightPadding, small.rightStrip - 10, "canvas grows only by the shortfall");
});

test("hair touching a side in the upper subject does not trigger horizontal fill", async () => {
  const geometry = await geometryOf(await subjectPng({ hairSpike: true }));
  assert.equal(geometry.shouldFill, false);
});

test("isolated boundary specks are not crops", () => {
  const specks = new Uint8Array(W * H);
  specks[40 * W] = 255;
  specks[55 * W] = 255;
  specks[70 * W] = 255;
  assert.equal(computeMinimalBodyFillGeometry(specks, W, H).shouldFill, false);
});

test("detects left, bottom and combined cropped edges", async () => {
  const left = await geometryOf(await subjectPng({ left: 60 }));
  assert.deepEqual(left.edges, { left: true, right: false, bottom: false });
  assert.equal(left.cropLeftX, 0);
  assert.equal(left.leftPadding, left.leftStrip);

  const bottom = await geometryOf(await subjectPng({ bottom: 170 }));
  assert.deepEqual(bottom.edges, { left: false, right: false, bottom: true });
  assert.equal(bottom.cropBottomY, 169);

  const combined = await geometryOf(await subjectPng({ left: 60, right: 140, bottom: 170 }));
  assert.deepEqual(combined.edges, { left: true, right: true, bottom: true });

  const inset = await geometryOf(
    await subjectPng({ left: 60, right: 140, bottom: 170, gutter: { left: 8, right: 80, bottom: 6 } }),
  );
  assert.deepEqual(inset.edges, { left: true, right: true, bottom: true });
  assert.equal(inset.leftPadding, inset.leftStrip - 8);
  assert.equal(inset.rightPadding, 0);
  assert.equal(inset.bottomPadding, inset.bottomStrip - 6);
});

test("preparation adds only the detected strip and returns its mapping", async () => {
  const png = await subjectPng({ right: 140 });
  const preparation = await prepareMinimalBodyFill(png);
  assert.equal(preparation.shouldFill, true);
  if (!preparation.shouldFill) return;

  assert.equal(preparation.mapping.originalX, 0);
  assert.equal(preparation.mapping.originalY, 0);
  assert.equal(preparation.mapping.originalWidth, 140);
  assert.equal(preparation.mapping.originalHeight, FH);
  assert.ok(preparation.mapping.canvasWidth > 140);
  assert.equal(preparation.mapping.canvasHeight, FH);

  const mask = await sharp(preparation.mask).removeAlpha().raw().toBuffer({
    resolveWithObject: true,
  });
  const sample = (x: number, y: number) => mask.data[(y * mask.info.width + x) * 3]!;
  assert.ok(sample(40, 140) < 16, "untouched source area stays black");
  assert.ok(sample((140 + mask.info.width) >> 1, 140) > 180, "new right strip is white");
});

test("gutter crop paints one strip past the crop line and keeps the canvas", async () => {
  const png = await subjectPng({ right: 140, gutter: { right: 60 } });
  const preparation = await prepareMinimalBodyFill(png);
  assert.equal(preparation.shouldFill, true);
  if (!preparation.shouldFill) return;
  assert.equal(preparation.mapping.canvasWidth, FW, "no canvas growth needed");
  assert.equal(preparation.mapping.originalX, 0);

  const mask = await sharp(preparation.mask).greyscale().raw().toBuffer({
    resolveWithObject: true,
  });
  const sample = (x: number, y: number) => mask.data[y * mask.info.width + x]!;
  assert.ok(sample(120, 140) < 16, "subject stays locked");
  assert.ok(sample(150, 140) > 180, "strip right of the crop line is paintable");
  assert.ok(sample(192, 140) < 16, "gutter beyond the strip is not painted");
});

test("client face box hard-locks the matching outpaint pixels", async () => {
  const png = await pngFromAlpha(alphaWithRect(60, 30, 100, 85));
  const preparation = await prepareMinimalBodyFill(png, {
    face: { x: 0.78, y: 0.32, width: 0.2, height: 0.2 },
  });
  assert.equal(preparation.shouldFill, true);
  if (!preparation.shouldFill) return;
  const mask = await sharp(preparation.mask).greyscale().raw().toBuffer({
    resolveWithObject: true,
  });
  const stripX = mask.info.width - 4;
  const sample = (y: number) => mask.data[y * mask.info.width + stripX]!;
  assert.ok(sample(45) < 16, "face-adjacent strip is never paint");
  assert.ok(sample(78) > 180, "body strip below the face remains paintable");
});

test("multiple-edge mask and mapping stay bounded to added strips", async () => {
  const png = await pngFromAlpha(alphaWithRect(0, 50, 100, 100));
  const preparation = await prepareMinimalBodyFill(png);
  assert.equal(preparation.shouldFill, true);
  if (!preparation.shouldFill) return;
  assert.deepEqual(preparation.edges, { left: true, right: true, bottom: true });
  assert.equal(preparation.mapping.originalX, 12);
  assert.equal(preparation.mapping.originalWidth, 100);
  assert.equal(preparation.mapping.canvasWidth, 124);
  assert.equal(preparation.mapping.canvasHeight, 116);

  const mask = await sharp(preparation.mask).greyscale().raw().toBuffer({
    resolveWithObject: true,
  });
  const sample = (x: number, y: number) => mask.data[y * mask.info.width + x]!;
  assert.ok(sample(3, 90) > 180, "left strip is paintable");
  assert.ok(sample(mask.info.width - 4, 90) > 180, "right strip is paintable");
  assert.ok(sample(mask.info.width >> 1, mask.info.height - 4) > 180, "bottom strip is paintable");
  assert.ok(sample(mask.info.width >> 1, 20) < 16, "unaffected source area stays locked");
});

test("restoration puts source pixels back over the generated strip", async () => {
  const png = await pngFromAlpha(alphaWithRect(60, 40, 100, 80));
  const preparation = await prepareMinimalBodyFill(png);
  assert.equal(preparation.shouldFill, true);
  if (!preparation.shouldFill) return;

  const generated = await sharp({
    create: {
      width: preparation.mapping.canvasWidth,
      height: preparation.mapping.canvasHeight,
      channels: 4,
      background: { r: 0, g: 180, b: 0, alpha: 1 },
    },
  }).png().toBuffer();
  const restored = await restoreMinimalBodyFillSubject(
    generated,
    preparation.personLayer,
    preparation.mapping,
  );
  const pixels = await sharp(restored).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const pixel = (x: number, y: number) => {
    const i = (y * pixels.info.width + x) * 4;
    return Array.from(pixels.data.subarray(i, i + 4));
  };

  assert.deepEqual(pixel(75, 60), [180, 40, 20, 255], "source subject is restored exactly");
  assert.deepEqual(
    pixel(pixels.info.width - 1, 60),
    [0, 180, 0, 255],
    "generated extension remains outside the source rect",
  );
});

test("native source pixels survive model-resolution downscaling", async () => {
  const width = 1200;
  const height = 900;
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 250; y < 700; y++) {
    for (let x = 700; x < width; x++) {
      const i = (y * width + x) * 4;
      rgba[i] = x % 251;
      rgba[i + 1] = y % 241;
      rgba[i + 2] = (x + y) % 239;
      rgba[i + 3] = 255;
    }
  }
  const softX = 650;
  const softY = 200;
  const softI = (softY * width + softX) * 4;
  rgba.set([17, 19, 23, 3], softI);
  const png = await sharp(rgba, {
    raw: { width, height, channels: 4 },
  }).png().toBuffer();
  const decodedSource = await sharp(png).ensureAlpha().raw().toBuffer();
  const preparation = await prepareMinimalBodyFill(png);
  assert.equal(preparation.shouldFill, true);
  if (!preparation.shouldFill) return;
  assert.equal(preparation.mapping.originalWidth, width);
  assert.equal(preparation.mapping.originalHeight, height);
  assert.ok((await sharp(preparation.padded).metadata()).width! < width);

  const generated = await sharp({
    create: {
      width: (await sharp(preparation.padded).metadata()).width!,
      height: (await sharp(preparation.padded).metadata()).height!,
      channels: 4,
      background: { r: 0, g: 180, b: 0, alpha: 1 },
    },
  }).png().toBuffer();
  const restored = await restoreMinimalBodyFillSubject(
    generated,
    preparation.personLayer,
    preparation.mapping,
  );
  const pixels = await sharp(restored).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const sourceX = 987;
  const sourceY = 543;
  const i = (sourceY * width + sourceX) * 4;
  const mappedI = (
    sourceY * pixels.info.width
    + preparation.mapping.originalX
    + sourceX
  ) * 4;
  assert.deepEqual(
    Array.from(pixels.data.subarray(mappedI, mappedI + 4)),
    Array.from(decodedSource.subarray(i, i + 4)),
  );
  const mappedSoftI = (
    softY * pixels.info.width
    + preparation.mapping.originalX
    + softX
  ) * 4;
  assert.deepEqual(
    Array.from(pixels.data.subarray(mappedSoftI, mappedSoftI + 4)),
    Array.from(decodedSource.subarray(softI, softI + 4)),
    "soft-alpha source pixels remain exact",
  );
});
