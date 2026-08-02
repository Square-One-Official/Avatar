// E41.4 smoke-driver: draai met `npx tsx scripts/image-smoke.ts` vanuit
// backend/. Puur lokaal (sharp) — geen netwerk, geen Replicate-calls.
//
// Bewijst de "perfect vrijstaand"-pipeline op een synthetische cutout:
// een rode schijf met zachte rand op transparant. Een naive grijs-flatten
// mengt de zachte rand ~50/50 met grijs (G/B ≈ 100); bleedFlatten moet daar
// vrijwel puur rood houden (G/B laag) — dat ís de anti-halo-garantie.
import assert from "node:assert";
import sharp from "sharp";
import {
  GPT_IMAGE_2_ASPECTS,
  bleedFlatten,
  capLongEdge,
  cropBackFromPad,
  flattenOnGrey,
  nearestFixedAspect,
  padToAspect,
  reapplyAlpha,
} from "../lib/image.js";

const W = 96;
const H = 96;
const CX = 48;
const CY = 48;
const R_OPAQUE = 20; // volledig opaak binnen deze straal
const R_ZERO = 32; // volledig transparant erbuiten; zachte ramp ertussen

function syntheticCutout(): Buffer {
  const raw = Buffer.alloc(W * H * 4);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const d = Math.hypot(x - CX, y - CY);
      let a = 0;
      if (d <= R_OPAQUE) a = 255;
      else if (d < R_ZERO) a = Math.round(255 * (R_ZERO - d) / (R_ZERO - R_OPAQUE));
      const i = (y * W + x) * 4;
      raw[i] = 255; // puur rood, ook waar transparant (straight alpha)
      raw[i + 1] = 0;
      raw[i + 2] = 0;
      raw[i + 3] = a;
    }
  }
  return raw;
}

const cutoutPng = await sharp(syntheticCutout(), { raw: { width: W, height: H, channels: 4 } })
  .png()
  .toBuffer();

const bled = await bleedFlatten(cutoutPng);
const naive = await flattenOnGrey(cutoutPng);
const bledRaw = (await sharp(bled).raw().toBuffer({ resolveWithObject: true }));
const naiveRaw = (await sharp(naive).raw().toBuffer({ resolveWithObject: true }));
assert.equal(bledRaw.info.channels, 3, "bleedFlatten hoort opake RGB te leveren");

function px(buf: Buffer, channels: number, x: number, y: number): number[] {
  const i = (y * W + x) * channels;
  return [buf[i], buf[i + 1], buf[i + 2]];
}

// 1. Opaak centrum: ongewijzigd puur rood.
{
  const [r, g, b] = px(bledRaw.data, 3, CX, CY);
  assert.ok(r >= 250 && g <= 5 && b <= 5, `centrum moet puur rood blijven, kreeg ${r},${g},${b}`);
}

// 2. Zachte rand (~50% alpha): naive flatten geeft hier G ≈ 100 (grijsmix);
//    bleed moet de grijsbijdrage vrijwel elimineren.
{
  const edgeX = CX + Math.round((R_OPAQUE + R_ZERO) / 2);
  const [, gBled] = px(bledRaw.data, 3, edgeX, CY);
  const [, gNaive] = px(naiveRaw.data, naiveRaw.info.channels, edgeX, CY);
  assert.ok(gNaive > 80, `sanity: naive flatten hoort ~100 grijs in de rand te mengen, kreeg ${gNaive}`);
  assert.ok(gBled < 25, `bleedFlatten laat grijs in de zachte rand achter (G=${gBled}, naive=${gNaive})`);
}

// 3. Ver van het onderwerp: neutraal grijs backdrop (zelfde als flattenOnGrey).
{
  const [r, g, b] = px(bledRaw.data, 3, 2, 2);
  for (const v of [r, g, b]) assert.ok(Math.abs(v - 200) <= 2, `hoek moet ~grijs 200 zijn, kreeg ${r},${g},${b}`);
}

// 4. reapplyAlpha op een 2×-geschaalde flatten: maat klopt, silhouet blijft
//    zacht (alpha ~50% in de rand, niet hard-gethreshold) en de randkleur
//    blijft rood.
{
  const upscaled = await sharp(bled).resize(W * 2, H * 2, { kernel: "lanczos3" }).png().toBuffer();
  const result = await reapplyAlpha(upscaled, cutoutPng);
  const { data, info } = await sharp(result).raw().toBuffer({ resolveWithObject: true });
  assert.equal(info.width, W * 2);
  assert.equal(info.channels, 4);
  const edgeX2 = (CX + Math.round((R_OPAQUE + R_ZERO) / 2)) * 2;
  const i = (CY * 2 * info.width + edgeX2) * 4;
  const [r, g, a] = [data[i], data[i + 1], data[i + 3]];
  assert.ok(a > 60 && a < 200, `randalpha moet zacht blijven (~128), kreeg ${a}`);
  assert.ok(r > 200 && g < 40, `randkleur moet rood blijven zonder grijswaas, kreeg r=${r} g=${g}`);
}

// 5. Volledig opake input: bleedFlatten is een no-op op de kleuren.
{
  const opaque = await sharp(Buffer.alloc(W * H * 4, 255), { raw: { width: W, height: H, channels: 4 } })
    .png()
    .toBuffer();
  const flat = await bleedFlatten(opaque);
  const { data } = await sharp(flat).raw().toBuffer({ resolveWithObject: true });
  assert.ok(data[0] === 255 && data[1] === 255 && data[2] === 255, "opake input moet ongewijzigd blijven");
}

// ---------------------------------------------------------------------------
// E55.1 — aspect-contract (pad → generate → crop). Het harde criterium:
// crop-back levert de exacte input-ratio terug (±1%, ruim onder de 2%-
// transform-reset-drempel van de client), voor elke output-pixelmaat.

/** Egaal rood opaak PNG op maat. */
async function solidRed(w: number, h: number): Promise<Buffer> {
  return sharp({ create: { width: w, height: h, channels: 3, background: { r: 255, g: 0, b: 0 } } })
    .png()
    .toBuffer();
}

// 6. nearestFixedAspect kiest de dichtstbijzijnde van 1:1 / 3:2 / 2:3.
{
  assert.equal(nearestFixedAspect(1000, 1000).key, "1:1");
  assert.equal(nearestFixedAspect(1500, 1000).key, "3:2");
  assert.equal(nearestFixedAspect(1000, 1500).key, "2:3");
  assert.equal(nearestFixedAspect(800, 1000).key, "2:3", "0.8 ligt dichter bij 2:3 dan bij 1:1");
  assert.equal(nearestFixedAspect(0, 0).key, "1:1", "degenerate input valt op de eerste ratio terug");
}

// 6b. gpt-image-2-set: 3:4/9:16 vangen portretten die op 1.5 nog dik moesten
//     padden — de kern van de dunner-pad-winst van de 2.0-swap.
{
  assert.equal(nearestFixedAspect(800, 1000, GPT_IMAGE_2_ASPECTS).key, "3:4");
  assert.equal(nearestFixedAspect(1080, 1920, GPT_IMAGE_2_ASPECTS).key, "9:16");
  assert.equal(nearestFixedAspect(1600, 1200, GPT_IMAGE_2_ASPECTS).key, "4:3");
  assert.equal(nearestFixedAspect(1000, 1000, GPT_IMAGE_2_ASPECTS).key, "1:1");
}

// 7. padToAspect: 800×1000 → 2:3-canvas (800×1200), bron gecentreerd, pad grijs.
{
  const src = await solidRed(800, 1000);
  const pad = await padToAspect(src, 2 / 3);
  assert.equal(pad.canvasW, 800);
  assert.equal(pad.canvasH, 1200);
  assert.equal(pad.left, 0);
  assert.equal(pad.top, 100);
  const { data, info } = await sharp(pad.padded).raw().toBuffer({ resolveWithObject: true });
  const at = (x: number, y: number) => {
    const i = (y * info.width + x) * info.channels;
    return [data[i], data[i + 1], data[i + 2]];
  };
  const [pr, pg, pb] = at(400, 10); // in de pad-strook boven de bron
  for (const v of [pr, pg, pb]) assert.ok(Math.abs(v - 200) <= 2, `pad-strook moet grijs 200 zijn, kreeg ${pr},${pg},${pb}`);
  const [sr, sg] = at(400, 600); // midden van de bron
  assert.ok(sr >= 250 && sg <= 5, "bronpixels moeten ongewijzigd door de pad heen");
}

// 8. Ratio al (vrijwel) goed → no-op, zelfde buffer terug.
{
  const src = await solidRed(1024, 1536);
  const pad = await padToAspect(src, 2 / 3);
  assert.equal(pad.padded, src, "exacte ratio hoort byte-identiek terug te komen");
  assert.equal(pad.canvasW, pad.srcW);
  const cropped = await cropBackFromPad(src, pad);
  assert.equal(cropped, src, "crop-back is een no-op zonder pad");
}

// 9. cropBackFromPad op een model-resultaat met ándere pixelmaat: gpt-image
//    levert het 2:3-canvas als 1024×1536 terug → terugsnijden naar bronregio
//    moet de input-ratio exact herstellen.
{
  const src = await solidRed(800, 1000);
  const pad = await padToAspect(src, 2 / 3);
  const modelResult = await solidRed(1024, 1536);
  const cropped = await cropBackFromPad(modelResult, pad);
  const meta = await sharp(cropped).metadata();
  const outRatio = (meta.width ?? 0) / (meta.height ?? 1);
  const srcRatio = 800 / 1000;
  assert.ok(
    Math.abs(outRatio - srcRatio) / srcRatio < 0.01,
    `crop-back-ratio ${outRatio.toFixed(4)} moet ±1% van bron-ratio ${srcRatio} zijn`,
  );
  assert.equal(meta.width, 1024, "volle canvasbreedte blijft staan (pad zat boven/onder)");
}

// 10. Oneven maten + alle drie de doel-ratio's: contract houdt overal.
{
  for (const [w, h] of [[801, 1001], [1001, 801], [997, 1003]] as const) {
    const src = await solidRed(w, h);
    const target = nearestFixedAspect(w, h);
    const pad = await padToAspect(src, target.ratio);
    const canvasRatio = pad.canvasW / pad.canvasH;
    assert.ok(
      Math.abs(canvasRatio - target.ratio) / target.ratio < 0.005,
      `canvas-ratio ${canvasRatio.toFixed(4)} moet ~${target.key} zijn voor ${w}x${h}`,
    );
    // Fake model-output op de vaste gpt-maat voor die ratio.
    const outDims = { "1:1": [1024, 1024], "3:2": [1536, 1024], "2:3": [1024, 1536] }[target.key];
    const cropped = await cropBackFromPad(await solidRed(outDims[0], outDims[1]), pad);
    const meta = await sharp(cropped).metadata();
    const outRatio = (meta.width ?? 0) / (meta.height ?? 1);
    const srcRatio = w / h;
    assert.ok(
      Math.abs(outRatio - srcRatio) / srcRatio < 0.015,
      `${w}x${h} via ${target.key}: crop-back-ratio ${outRatio.toFixed(4)} wijkt >1.5% af van ${srcRatio.toFixed(4)}`,
    );
  }
}

// 11. capLongEdge: boven de cap geschaald (ratio + alpha behouden), eronder
//     byte-identiek terug.
{
  const big = await sharp({
    create: { width: 4096, height: 2048, channels: 4, background: { r: 0, g: 255, b: 0, alpha: 0.5 } },
  })
    .png()
    .toBuffer();
  const capped = await capLongEdge(big, 2048);
  const meta = await sharp(capped).metadata();
  assert.equal(meta.width, 2048);
  assert.equal(meta.height, 1024);
  assert.ok((meta.channels ?? 0) >= 4 || meta.hasAlpha, "alpha moet de cap overleven");
  const small = await solidRed(640, 480);
  assert.equal(await capLongEdge(small, 2048), small, "onder de cap hoort byte-identiek terug");
}

console.log("image.ts smoke OK (bleedFlatten + reapplyAlpha + aspect-contract E55.1)");
