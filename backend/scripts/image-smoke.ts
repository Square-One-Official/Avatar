// E41.4 smoke-driver: draai met `npx tsx scripts/image-smoke.ts` vanuit
// backend/. Puur lokaal (sharp) — geen netwerk, geen Replicate-calls.
//
// Bewijst de "perfect vrijstaand"-pipeline op een synthetische cutout:
// een rode schijf met zachte rand op transparant. Een naive grijs-flatten
// mengt de zachte rand ~50/50 met grijs (G/B ≈ 100); bleedFlatten moet daar
// vrijwel puur rood houden (G/B laag) — dat ís de anti-halo-garantie.
import assert from "node:assert";
import sharp from "sharp";
import { bleedFlatten, flattenOnGrey, reapplyAlpha } from "../lib/image.js";

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

console.log("image.ts smoke OK (bleedFlatten + reapplyAlpha)");
