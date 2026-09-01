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

test("central subject is a non-billable no-op", async () => {
  const png = await pngFromAlpha(alphaWithRect(30, 30, 70, 80));
  const preparation = await prepareMinimalBodyFill(png);
  assert.equal(preparation.shouldFill, false);
  if (preparation.shouldFill) return;
  assert.deepEqual(preparation.edges, { left: false, right: false, bottom: false });
  assert.equal(preparation.cutout.compare(png), 0);
});

test("detects only a meaningful right-edge body crop", () => {
  const geometry = computeMinimalBodyFillGeometry(alphaWithRect(60, 40, 100, 80), W, H);
  assert.equal(geometry.shouldFill, true);
  assert.deepEqual(geometry.edges, { left: false, right: true, bottom: false });
  assert.ok(geometry.rightPadding > 0);
  assert.equal(geometry.leftPadding, 0);
  assert.equal(geometry.bottomPadding, 0);
});

test("top-edge hair does not trigger horizontal body fill", () => {
  const geometry = computeMinimalBodyFillGeometry(alphaWithRect(0, 0, 15, 20), W, H);
  assert.equal(geometry.shouldFill, false);
});

test("transparent gutter and isolated boundary specks are not crops", () => {
  const gutter = computeMinimalBodyFillGeometry(alphaWithRect(2, 40, 40, 80), W, H);
  assert.equal(gutter.shouldFill, false);

  const specks = new Uint8Array(W * H);
  specks[40 * W] = 255;
  specks[55 * W] = 255;
  specks[70 * W] = 255;
  assert.equal(computeMinimalBodyFillGeometry(specks, W, H).shouldFill, false);
});

test("detects left, bottom and combined cropped edges", () => {
  const left = computeMinimalBodyFillGeometry(alphaWithRect(0, 45, 35, 80), W, H);
  assert.deepEqual(left.edges, { left: true, right: false, bottom: false });

  const bottom = computeMinimalBodyFillGeometry(alphaWithRect(35, 55, 65, 100), W, H);
  assert.deepEqual(bottom.edges, { left: false, right: false, bottom: true });

  const combined = computeMinimalBodyFillGeometry(alphaWithRect(0, 45, 100, 100), W, H);
  assert.deepEqual(combined.edges, { left: true, right: true, bottom: true });
});

test("preparation adds only the detected strip and returns its mapping", async () => {
  const png = await pngFromAlpha(alphaWithRect(60, 40, 100, 80));
  const preparation = await prepareMinimalBodyFill(png);
  assert.equal(preparation.shouldFill, true);
  if (!preparation.shouldFill) return;

  assert.equal(preparation.mapping.originalX, 0);
  assert.equal(preparation.mapping.originalY, 0);
  assert.equal(preparation.mapping.originalWidth, W);
  assert.equal(preparation.mapping.originalHeight, H);
  assert.ok(preparation.mapping.canvasWidth > W);
  assert.equal(preparation.mapping.canvasHeight, H);

  const mask = await sharp(preparation.mask).removeAlpha().raw().toBuffer({
    resolveWithObject: true,
  });
  const sample = (x: number, y: number) => mask.data[(y * mask.info.width + x) * 3]!;
  assert.ok(sample(20, 50) < 16, "untouched source area stays black");
  assert.ok(sample((W + mask.info.width) >> 1, 70) > 180, "new right strip is white");
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
