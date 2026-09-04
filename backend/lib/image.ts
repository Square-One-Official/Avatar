import sharp from "sharp";

// sharp 0.35 stopte met het `sharp.X`-namespace-type onder ESM-import;
// afleiden uit de API zelf houdt dit los van hoe de typings verpakt zijn.
type SharpOverlayOptions = Parameters<ReturnType<typeof sharp>["composite"]>[0][number];

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
 * Pixel-count ceiling for any image we hand to `sharp`. A small payload can
 * still decode to an enormous raster (a "decompression bomb"), so the byte
 * cap above is not sufficient on its own. 50 MP is ~7000×7000 — far above any
 * legitimate portrait the app produces (the outpaint canvas is 768×1024),
 * while still rejecting pathological inputs before sharp allocates for them.
 */
export const MAX_INPUT_IMAGE_PIXELS = 50_000_000;

/**
 * E41.5: schaal een PNG terug tot maximaal `maxPixels` beeldpunten (aspect
 * behouden, lanczos3). Kosten-cap voor het Topaz-pad: Topaz rekent per
 * OUTPUT-megapixel ($0,05 t/m 24 MP, daarboven duurder) — 6 MP input × 2×
 * blijft precies binnen de laagste unit. Onder de cap komt het origineel
 * byte-identiek terug (geen her-encode).
 */
export async function capPixels(png: Buffer, maxPixels: number): Promise<Buffer> {
  const meta = await sharp(png).metadata();
  const w = meta.width ?? 0;
  const h = meta.height ?? 0;
  if (w <= 0 || h <= 0 || w * h <= maxPixels) return png;
  const scale = Math.sqrt(maxPixels / (w * h));
  const newW = Math.max(1, Math.floor(w * scale));
  return sharp(png)
    .resize({ width: newW, kernel: "lanczos3" })
    .png()
    .toBuffer();
}

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
 * E55.1 — engine-agnostisch aspect-contract voor /v1/stylize.
 *
 * gpt-image kent geen `match_input_image`; het snapt naar een vaste set
 * ratio's en herkadert daarmee élk portret dat daar niet op ligt — precies
 * wat de client-side transform-reset triggert (ShellModel.storeEffectResult,
 * drift ≥ 2%). Het contract hier draait dat om: pad de input naar de
 * dichtstbijzijnde ondersteunde ratio (gecentreerde letterbox op hetzelfde
 * studio-grijs als flattenOnGrey), laat het model op dat kader werken, en
 * crop het resultaat proportioneel terug naar de exacte input-ratio.
 * Response-aspect == request-aspect, voor elke engine.
 */

// Ratio-sets + types leven sinds de gpt-image-2-swap in lib/aspects.ts (pure
// data, geen sharp) — re-export voor bestaande importeurs.
export { GPT_IMAGE_ASPECTS, GPT_IMAGE_2_ASPECTS } from "./aspects.js";
export type { FixedAspect, FixedAspectKey } from "./aspects.js";
import { GPT_IMAGE_ASPECTS, type FixedAspect } from "./aspects.js";

/** Kies de ondersteunde ratio die het dichtst bij width/height ligt. */
export function nearestFixedAspect(
  width: number,
  height: number,
  aspects: FixedAspect[] = GPT_IMAGE_ASPECTS,
): FixedAspect {
  if (width <= 0 || height <= 0) return aspects[0];
  const ratio = width / height;
  return [...aspects].sort(
    (a, b) => Math.abs(a.ratio - ratio) - Math.abs(b.ratio - ratio),
  )[0];
}

/**
 * Boekhouding van een aspect-pad: waar de bron binnen het gepadde canvas
 * ligt, zodat `cropBackFromPad` het modelresultaat (op wélke pixelmaat dan
 * ook) proportioneel kan terugsnijden naar de bronregio.
 */
export interface AspectPad {
  padded: Buffer;
  srcW: number;
  srcH: number;
  canvasW: number;
  canvasH: number;
  left: number;
  top: number;
}

/**
 * Ratio-verschil waaronder padden niet loont: het model-snapje zelf blijft
 * dan ruim onder de 2%-reset-drempel van de client, en een pad-strook van
 * enkele pixels voegt alleen een naadje toe.
 */
const PAD_EPSILON = 0.005;

/** Pad `png` gecentreerd op studio-grijs naar exact `targetRatio` (w/h). */
export async function padToAspect(png: Buffer, targetRatio: number): Promise<AspectPad> {
  const meta = await sharp(png).metadata();
  const w = meta.width ?? 0;
  const h = meta.height ?? 0;
  if (w <= 0 || h <= 0) throw new Error("padToAspect: source has no dimensions");
  const noop = { padded: png, srcW: w, srcH: h, canvasW: w, canvasH: h, left: 0, top: 0 };
  if (targetRatio <= 0) return noop;
  const current = w / h;
  if (Math.abs(current - targetRatio) / targetRatio < PAD_EPSILON) return noop;
  let canvasW = w;
  let canvasH = h;
  if (current < targetRatio) {
    canvasW = Math.round(h * targetRatio);
  } else {
    canvasH = Math.round(w / targetRatio);
  }
  const left = Math.floor((canvasW - w) / 2);
  const top = Math.floor((canvasH - h) / 2);
  const padded = await sharp({
    create: {
      width: canvasW,
      height: canvasH,
      channels: 4,
      background: { ...GREY, alpha: 1 },
    },
  })
    .composite([{ input: png, left, top }])
    .flatten({ background: GREY })
    .png()
    .toBuffer();
  return { padded, srcW: w, srcH: h, canvasW, canvasH, left, top };
}

/**
 * Snijd het modelresultaat terug naar de bronregio van `pad`. Het resultaat
 * mag een andere pixelmaat hebben dan het gepadde canvas (gpt-image levert
 * vaste outputmaten) — de mapping is proportioneel per as, geklemd op de
 * resultaatgrenzen. No-op wanneer er niet gepad is of niets te snijden valt.
 */
export async function cropBackFromPad(resultPng: Buffer, pad: AspectPad): Promise<Buffer> {
  if (pad.canvasW === pad.srcW && pad.canvasH === pad.srcH) return resultPng;
  const meta = await sharp(resultPng).metadata();
  const rw = meta.width ?? 0;
  const rh = meta.height ?? 0;
  if (rw <= 0 || rh <= 0) return resultPng;
  // Weigering-guard (E55-edge-sweep): wijkt de resultaat-ratio >2% af van de
  // canvas-ratio, dan heeft het model de gevraagde ratio genegeerd en zou de
  // proportionele terugsnede de verkéérde regio pakken (content-verlies).
  // Liever ongecropt terug — de client reset dan transform + herkadert (het
  // pre-E55-gedrag) — en luid loggen zodat het in de bakeoff/prod opvalt.
  const canvasRatio = pad.canvasW / pad.canvasH;
  const resultRatio = rw / rh;
  if (Math.abs(resultRatio - canvasRatio) / canvasRatio > 0.02) {
    console.warn(
      `[image] cropBackFromPad: resultaat-ratio ${resultRatio.toFixed(4)} ≠ canvas-ratio ${canvasRatio.toFixed(4)} — model negeerde de gevraagde ratio, crop overgeslagen`,
    );
    return resultPng;
  }
  const sx = rw / pad.canvasW;
  const sy = rh / pad.canvasH;
  let width = Math.min(rw, Math.max(1, Math.round(pad.srcW * sx)));
  let height = Math.min(rh, Math.max(1, Math.round(pad.srcH * sy)));
  const left = Math.min(Math.max(0, Math.round(pad.left * sx)), rw - width);
  const top = Math.min(Math.max(0, Math.round(pad.top * sy)), rh - height);
  if (left === 0 && top === 0 && width === rw && height === rh) return resultPng;
  return sharp(resultPng).extract({ left, top, width, height }).png().toBuffer();
}

/**
 * E55.1: cap de langste zijde op `maxEdge` (lanczos3, alpha behouden).
 * Instruction-edit-modellen leveren toch ~1–1.5 MP terug; >2048px input
 * koopt alleen upload-latency en ingest-kosten. Onder de cap komt het
 * origineel byte-identiek terug (zelfde patroon als capPixels).
 */
export async function capLongEdge(png: Buffer, maxEdge: number): Promise<Buffer> {
  const meta = await sharp(png).metadata();
  const w = meta.width ?? 0;
  const h = meta.height ?? 0;
  if (w <= 0 || h <= 0 || Math.max(w, h) <= maxEdge) return png;
  return sharp(png)
    .resize(
      w >= h
        ? { width: maxEdge, kernel: "lanczos3" }
        : { height: maxEdge, kernel: "lanczos3" },
    )
    .png()
    .toBuffer();
}

/**
 * E41.4: flatten voor de upscale-route, zónder de grijze halo die een naive
 * flatten in zachte randen bakt.
 *
 * Een halfdoorzichtige haarpixel draagt zijn eigen kleur, maar
 * `flatten({ background: grijs })` mengt hem met grijs. Na de RGB-upscale
 * hangt reapplyAlpha het masker terug en blijft dat grijs in de RGB zitten —
 * zichtbaar als een vale waas rond haar. Oplossing: bouw eerst een
 * "edge-bleed"-veld door de gepremultipliceerde RGB en de alpha met dezelfde
 * sigma te blurren en te delen (de klassieke solidify/push-pull-truc uit
 * texture-pipelines). Elke (half)transparante pixel nabij het onderwerp krijgt
 * zo de kleur van de dichtstbijzijnde opake pixels; de cutout daaroverheen
 * componeren mengt haar met haarkleur i.p.v. met grijs. Buiten het
 * blur-bereik valt de achtergrond terug op hetzelfde neutrale grijs als
 * flattenOnGrey (studio-backdrop voor het model).
 */
export async function bleedFlatten(cutoutPng: Buffer): Promise<Buffer> {
  const { data, info } = await sharp(cutoutPng)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const { width, height } = info;
  const n = width * height;

  // Premultiplied RGB + alpha als losse vlakken voor de blur. De alpha gaat
  // als (a,a,a)-drieband door EXACT dezelfde 3-kanaals blur-pijplijn als de
  // premult: sharp/vips blurt 1-kanaals ("b-w") beelden aantoonbaar anders
  // dan 3-kanaals, en elke asymmetrie sloopt de premult/alpha-ratio waar de
  // uitgesmeerde kleur uit komt. Identieke pijplijnen ⇒ exacte ratio.
  const premult = Buffer.alloc(n * 3);
  const alpha3 = Buffer.alloc(n * 3);
  for (let i = 0; i < n; i++) {
    const a = data[i * 4 + 3];
    alpha3[i * 3] = a;
    alpha3[i * 3 + 1] = a;
    alpha3[i * 3 + 2] = a;
    premult[i * 3] = (data[i * 4] * a / 255) | 0;
    premult[i * 3 + 1] = (data[i * 4 + 1] * a / 255) | 0;
    premult[i * 3 + 2] = (data[i * 4 + 2] * a / 255) | 0;
  }

  // Bereik ~3σ ≈ 36px — ruim onder/rond een haarrand, klein t.o.v. het beeld.
  const BLEED_SIGMA = 12;
  const [blurredPremult, blurredAlpha] = await Promise.all([
    sharp(premult, { raw: { width, height, channels: 3 } })
      .blur(BLEED_SIGMA)
      .raw()
      .toBuffer(),
    sharp(alpha3, { raw: { width, height, channels: 3 } })
      .blur(BLEED_SIGMA)
      .raw()
      .toBuffer(),
  ]);

  const GREY = 200; // zelfde backdrop als flattenOnGrey
  const out = Buffer.alloc(n * 3);
  for (let i = 0; i < n; i++) {
    const a = data[i * 4 + 3] / 255;
    const ba = blurredAlpha[i * 3];
    for (let c = 0; c < 3; c++) {
      // Unpremultiply van het geblurde veld = uitgesmeerde randkleur; bij
      // (bijna) nul geblurde alpha is de deling ruis → neutraal grijs.
      const ext = ba > 8 ? Math.min(255, (blurredPremult[i * 3 + c] * 255) / ba) : GREY;
      out[i * 3 + c] = Math.round(data[i * 4 + c] * a + ext * (1 - a));
    }
  }
  return sharp(out, { raw: { width, height, channels: 3 } }).png().toBuffer();
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
  // E41.4: NIET via sharp's joinChannel — die dropt in 0.33.5 stilletjes het
  // aangeleverde kanaal (output blijft 3-kanaals, geen error) wanneer de
  // alpha uit extractChannel komt. Gevolg in productie: /v1/colorize en
  // /v1/upscale gaven een opaque grijs-backdrop-beeld terug en de client
  // moest het onderwerp opnieuw uitknippen (zichtbaar slechtere haarranden).
  // Daarom: kanalen zelf interleaven op raw buffers — bewijsbaar RGBA.
  const color = await sharp(colorizedRgb)
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const { width: w, height: h } = color.info;
  if (!w || !h) {
    throw new Error("reapplyAlpha: colorized image has no dimensions");
  }
  const alpha = await sharp(originalRgba)
    .ensureAlpha()
    .extractChannel("alpha")
    .resize(w, h, { fit: "fill" })
    .raw()
    .toBuffer();
  const n = w * h;
  const out = Buffer.alloc(n * 4);
  for (let i = 0; i < n; i++) {
    out[i * 4] = color.data[i * 3];
    out[i * 4 + 1] = color.data[i * 3 + 1];
    out[i * 4 + 2] = color.data[i * 3 + 2];
    out[i * 4 + 3] = alpha[i];
  }
  return sharp(out, { raw: { width: w, height: h, channels: 4 } })
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

export interface FillBodyEdges {
  left: boolean;
  right: boolean;
  bottom: boolean;
}

export interface FillBodyMapping {
  canvasWidth: number;
  canvasHeight: number;
  originalX: number;
  originalY: number;
  originalWidth: number;
  originalHeight: number;
}

export interface FillBodyGeometry {
  shouldFill: boolean;
  edges: FillBodyEdges;
  /** Canvas growth (px, source scale) beyond the existing image bounds. */
  leftPadding: number;
  rightPadding: number;
  bottomPadding: number;
  /**
   * Crop lines in source pixel coords: the outermost solid alpha column/row
   * of the subject on each detected edge. -1 when that edge is not cropped.
   */
  cropLeftX: number;
  cropRightX: number;
  cropBottomY: number;
  /** Fill strip width per edge (px, source scale), measured from the crop line. */
  leftStrip: number;
  rightStrip: number;
  bottomStrip: number;
  seam: number;
  /**
   * Solid subject extent along each crop line (source px, inclusive): the
   * first/last solid alpha row on a cropped side column, the first/last solid
   * alpha column on the cropped bottom row. -1 when that edge is not cropped.
   * Bounds the mask strip to the body (E56.3) — a strip over the full canvas
   * width reads as a caption bar to the model and gets filled with text.
   */
  leftRunStart: number;
  leftRunEnd: number;
  rightRunStart: number;
  rightRunEnd: number;
  bottomRunStart: number;
  bottomRunEnd: number;
}

export type MinimalBodyFillPreparation =
  | {
      shouldFill: false;
      cutout: Buffer;
      edges: FillBodyEdges;
      mapping: FillBodyMapping;
    }
  | {
      shouldFill: true;
      padded: Buffer;
      mask: Buffer;
      personLayer: Buffer;
      edges: FillBodyEdges;
      mapping: FillBodyMapping;
    };

/** Alpha at/above this counts as solid subject for crop-line detection. */
const SOLID_ALPHA = 128;
/** Alpha at/above this counts as subject for the bbox (matches the client's trim). */
const SUBJECT_ALPHA = 16;

/**
 * Detect meaningful crop lines on the three body-extension edges of the
 * *subject*, not of the canvas. Top is deliberately excluded: Fill in body
 * may complete shoulders, arms and torso, but must never invent hair or
 * facial pixels.
 *
 * A crop line is the outermost solid (alpha ≥ 128) column/row of the alpha
 * bbox with a long contiguous run of solid pixels on it. A natural matte edge
 * (rounded shoulder, soft BiRefNet/Vision boundary) only touches its extreme
 * column for a few pixels; a crop is a long, straight line. Looking at the
 * subject instead of the canvas means a transparent gutter — an import with
 * padding, or the unfilled margin a previous Fill in body left behind — no
 * longer hides the cut (E56.2). Side detection ignores the upper 30% of the
 * subject so hair touching a side does not turn into a horizontal outpaint.
 */
export function computeMinimalBodyFillGeometry(
  alpha: Uint8Array,
  width: number,
  height: number,
): FillBodyGeometry {
  const none: FillBodyGeometry = {
    shouldFill: false,
    edges: { left: false, right: false, bottom: false },
    leftPadding: 0,
    rightPadding: 0,
    bottomPadding: 0,
    cropLeftX: -1,
    cropRightX: -1,
    cropBottomY: -1,
    leftStrip: 0,
    rightStrip: 0,
    bottomStrip: 0,
    seam: 0,
    leftRunStart: -1,
    leftRunEnd: -1,
    rightRunStart: -1,
    rightRunEnd: -1,
    bottomRunStart: -1,
    bottomRunEnd: -1,
  };
  if (width <= 0 || height <= 0 || alpha.length < width * height) return none;

  // Subject bbox (soft threshold) and solid bbox (hard threshold).
  let top = height, bottom = -1;
  let solidLeft = width, solidRight = -1, solidBottom = -1;
  for (let y = 0; y < height; y++) {
    const row = y * width;
    for (let x = 0; x < width; x++) {
      const a = alpha[row + x]!;
      if (a < SUBJECT_ALPHA) continue;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
      if (a >= SOLID_ALPHA) {
        if (x < solidLeft) solidLeft = x;
        if (x > solidRight) solidRight = x;
        if (y > solidBottom) solidBottom = y;
      }
    }
  }
  if (bottom < 0 || solidRight < 0) return none;

  const subjectHeight = bottom - top + 1;
  const sideStartY = Math.min(bottom, top + Math.round(subjectHeight * 0.3));
  const sampledRows = bottom - sideStartY + 1;
  // A natural silhouette touches its extreme column for ~sqrt(1/r) of its
  // height (≈5–8% for a real shoulder); a cropped arm is a far longer line.
  const sideNeed = Math.max(6, Math.round(sampledRows * 0.12));
  const solidWidth = solidRight - solidLeft + 1;
  // A cropped torso is cut over most of its width; an elliptical torso
  // bottom is flat for ~15% at most.
  const bottomNeed = Math.max(6, Math.round(solidWidth * 0.3));

  const longestColumnRun = (x: number): number => {
    let current = 0;
    let longest = 0;
    for (let y = sideStartY; y <= bottom; y++) {
      if (alpha[y * width + x]! >= SOLID_ALPHA) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 0;
      }
    }
    return longest;
  };
  const longestRowRun = (y: number): number => {
    let current = 0;
    let longest = 0;
    const row = y * width;
    for (let x = 0; x < width; x++) {
      if (alpha[row + x]! >= SOLID_ALPHA) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 0;
      }
    }
    return longest;
  };

  // A crop line is a long solid run that ends abruptly: the line just outside
  // it carries (almost) nothing. A natural curve grows its runs gradually
  // inward, so the ratio test rejects it even when the extreme line itself
  // is flat enough to pass the length test.
  const searchDepthX = Math.max(3, Math.round(width * 0.02));
  const searchDepthY = Math.max(3, Math.round(height * 0.02));
  const ABRUPT_RATIO = 3;
  const findCropColumn = (from: number, step: 1 | -1): number => {
    for (let i = 0; i < searchDepthX; i++) {
      const x = from + i * step;
      if (x < 0 || x >= width) break;
      const run = longestColumnRun(x);
      if (run < sideNeed) continue;
      const outerX = x - step;
      const outer = outerX < 0 || outerX >= width ? 0 : longestColumnRun(outerX);
      if (run >= outer * ABRUPT_RATIO) return x;
    }
    return -1;
  };
  const findCropRow = (from: number): number => {
    for (let i = 0; i < searchDepthY; i++) {
      const y = from - i;
      if (y < 0) break;
      const run = longestRowRun(y);
      if (run < bottomNeed) continue;
      const outer = y + 1 >= height ? 0 : longestRowRun(y + 1);
      if (run >= outer * ABRUPT_RATIO) return y;
    }
    return -1;
  };

  const cropLeftX = findCropColumn(solidLeft, 1);
  const cropRightX = findCropColumn(solidRight, -1);
  const cropBottomY = findCropRow(solidBottom);
  const edges: FillBodyEdges = {
    left: cropLeftX >= 0,
    right: cropRightX >= 0,
    bottom: cropBottomY >= 0,
  };
  const shouldFill = edges.left || edges.right || edges.bottom;
  if (!shouldFill) return none;

  // Repair one clipped body segment rather than creating a full portrait.
  // The strip is measured from the crop line; the canvas only grows where the
  // existing transparent margin is too small to hold it.
  const sideStrip = Math.max(12, Math.round(width * 0.12));
  const bottomStrip = Math.max(16, Math.round(height * 0.14));
  const leftStrip = edges.left ? sideStrip : 0;
  const rightStrip = edges.right ? sideStrip : 0;
  const bottomStripPx = edges.bottom ? bottomStrip : 0;

  // Solid extent along each crop line, so the strips hug the body instead of
  // spanning the whole canvas edge (E56.3).
  const columnExtent = (x: number): [number, number] => {
    let start = -1, end = -1;
    for (let y = 0; y < height; y++) {
      if (alpha[y * width + x]! >= SOLID_ALPHA) {
        if (start < 0) start = y;
        end = y;
      }
    }
    return [start, end];
  };
  const rowExtent = (y: number): [number, number] => {
    let start = -1, end = -1;
    const row = y * width;
    for (let x = 0; x < width; x++) {
      if (alpha[row + x]! >= SOLID_ALPHA) {
        if (start < 0) start = x;
        end = x;
      }
    }
    return [start, end];
  };
  const [leftRunStart, leftRunEnd] = edges.left ? columnExtent(cropLeftX) : [-1, -1];
  const [rightRunStart, rightRunEnd] = edges.right ? columnExtent(cropRightX) : [-1, -1];
  const [bottomRunStart, bottomRunEnd] = edges.bottom ? rowExtent(cropBottomY) : [-1, -1];

  return {
    shouldFill,
    edges,
    leftPadding: edges.left ? Math.max(0, leftStrip - cropLeftX) : 0,
    rightPadding: edges.right ? Math.max(0, cropRightX + 1 + rightStrip - width) : 0,
    bottomPadding: edges.bottom ? Math.max(0, cropBottomY + 1 + bottomStripPx - height) : 0,
    cropLeftX,
    cropRightX,
    cropBottomY,
    leftStrip,
    rightStrip,
    bottomStrip: bottomStripPx,
    seam: Math.max(4, Math.min(10, Math.round(Math.min(width, height) * 0.008))),
    leftRunStart,
    leftRunEnd,
    rightRunStart,
    rightRunEnd,
    bottomRunStart,
    bottomRunEnd,
  };
}

/**
 * Prepare a minimal edge-aware FLUX Fill canvas while retaining the original
 * source pixels and their exact position in the returned native-size canvas.
 */
export async function prepareMinimalBodyFill(
  cutoutPng: Buffer,
  options?: { face?: FaceBox },
): Promise<MinimalBodyFillPreparation> {
  const src = sharp(cutoutPng).ensureAlpha();
  const meta = await src.metadata();
  if (!meta.width || !meta.height) {
    throw new Error("prepareMinimalBodyFill: source has no dimensions");
  }

  const alpha = await sharp(cutoutPng)
    .ensureAlpha()
    .extractChannel("alpha")
    .raw()
    .toBuffer();
  const geometry = computeMinimalBodyFillGeometry(alpha, meta.width, meta.height);
  if (!geometry.shouldFill) {
    return {
      shouldFill: false,
      cutout: cutoutPng,
      edges: geometry.edges,
      mapping: {
        canvasWidth: meta.width,
        canvasHeight: meta.height,
        originalX: 0,
        originalY: 0,
        originalWidth: meta.width,
        originalHeight: meta.height,
      },
    };
  }

  // Keep generation near one megapixel, but preserve the clean source at
  // native resolution in personLayer and in the final mapping.
  const nativeCanvasWidth = meta.width + geometry.leftPadding + geometry.rightPadding;
  const nativeCanvasHeight = meta.height + geometry.bottomPadding;
  const sourceScale = Math.min(1, 1024 / Math.max(nativeCanvasWidth, nativeCanvasHeight));
  const drawW = Math.max(1, Math.round(meta.width * sourceScale));
  const drawH = Math.max(1, Math.round(meta.height * sourceScale));
  const modelLeftPadding = geometry.edges.left
    ? Math.max(1, Math.round(geometry.leftPadding * sourceScale))
    : 0;
  const modelRightPadding = geometry.edges.right
    ? Math.max(1, Math.round(geometry.rightPadding * sourceScale))
    : 0;
  const modelBottomPadding = geometry.edges.bottom
    ? Math.max(1, Math.round(geometry.bottomPadding * sourceScale))
    : 0;
  const seam = Math.max(1, Math.round(geometry.seam * sourceScale));
  const modelCanvasWidth = drawW + modelLeftPadding + modelRightPadding;
  const modelCanvasHeight = drawH + modelBottomPadding;
  const mapping: FillBodyMapping = {
    canvasWidth: nativeCanvasWidth,
    canvasHeight: nativeCanvasHeight,
    originalX: geometry.leftPadding,
    originalY: 0,
    originalWidth: meta.width,
    originalHeight: meta.height,
  };

  const resized = await sharp(cutoutPng)
    .ensureAlpha()
    .resize(drawW, drawH, { fit: "fill" })
    .png()
    .toBuffer();

  const personLayer = await sharp({
    create: {
      width: nativeCanvasWidth,
      height: nativeCanvasHeight,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([{ input: cutoutPng, left: geometry.leftPadding, top: 0 }])
    .png()
    .toBuffer();

  const padded = await sharp({
    create: {
      width: modelCanvasWidth,
      height: modelCanvasHeight,
      channels: 4,
      background: { ...GREY, alpha: 1 },
    },
  })
    .composite([{ input: resized, left: modelLeftPadding, top: 0 }])
    .flatten({ background: GREY })
    .png()
    .toBuffer();

  const whiteRect = async (width: number, height: number): Promise<Buffer> =>
    sharp({
      create: {
        width: Math.max(1, width),
        height: Math.max(1, height),
        channels: 3,
        background: { r: 255, g: 255, b: 255 },
      },
    }).png().toBuffer();

  // White = paint. Each strip starts a seam-width inside the crop line (so
  // the model blends into the last real pixels) and runs one strip outward,
  // no farther: a wide transparent gutter is not an invitation to paint a
  // full body. Along the crop line the strip hugs the solid subject plus one
  // strip depth of margin on either end (room for a shoulder or sleeve to
  // widen), and only runs into the canvas corner when the adjoining edge is
  // cropped too (E56.3). A strip across the whole bottom of a portrait reads
  // as a subtitle/caption bar to FLUX and came back with hallucinated text.
  const toModelX = (sourceX: number) => modelLeftPadding + Math.round(sourceX * sourceScale);
  const toModelY = (sourceY: number) => Math.round(sourceY * sourceScale);
  const fillLayers: SharpOverlayOptions[] = [];
  const sideSpan = (runStart: number, runEnd: number, strip: number): [number, number] => {
    const margin = Math.round(strip * sourceScale);
    const top = Math.max(0, toModelY(runStart) - margin);
    const bottom = geometry.edges.bottom
      ? modelCanvasHeight
      : Math.min(modelCanvasHeight, toModelY(runEnd + 1) + margin);
    return [top, bottom];
  };
  if (geometry.edges.left) {
    const lineX = toModelX(geometry.cropLeftX);
    const from = Math.max(0, lineX - Math.round(geometry.leftStrip * sourceScale));
    const to = Math.min(modelCanvasWidth, lineX + seam);
    const [top, bottom] = sideSpan(geometry.leftRunStart, geometry.leftRunEnd, geometry.leftStrip);
    fillLayers.push({ input: await whiteRect(to - from, bottom - top), left: from, top });
  }
  if (geometry.edges.right) {
    const lineX = toModelX(geometry.cropRightX + 1);
    const from = Math.max(0, lineX - seam);
    const to = Math.min(modelCanvasWidth, lineX + Math.round(geometry.rightStrip * sourceScale));
    const [top, bottom] = sideSpan(geometry.rightRunStart, geometry.rightRunEnd, geometry.rightStrip);
    fillLayers.push({ input: await whiteRect(to - from, bottom - top), left: from, top });
  }
  if (geometry.edges.bottom) {
    const lineY = toModelY(geometry.cropBottomY + 1);
    const from = Math.max(0, lineY - seam);
    const to = Math.min(modelCanvasHeight, lineY + Math.round(geometry.bottomStrip * sourceScale));
    const margin = Math.round(geometry.bottomStrip * sourceScale);
    const left = geometry.edges.left
      ? 0
      : Math.max(0, toModelX(geometry.bottomRunStart) - margin);
    const right = geometry.edges.right
      ? modelCanvasWidth
      : Math.min(modelCanvasWidth, toModelX(geometry.bottomRunEnd + 1) + margin);
    fillLayers.push({ input: await whiteRect(right - left, to - from), left, top: from });
  }

  const featheredMask = await sharp({
    create: {
      width: modelCanvasWidth,
      height: modelCanvasHeight,
      channels: 3,
      background: { r: 0, g: 0, b: 0 },
    },
  }).composite(fillLayers).blur(2).png().toBuffer();

  const trimmed = await sharp(cutoutPng)
    .ensureAlpha()
    .trim({ background: { r: 0, g: 0, b: 0, alpha: 0 }, threshold: 1 })
    .toBuffer({ resolveWithObject: true });
  const guard = computeMinimalFaceGuardRect({
    face: options?.face,
    inputWidth: meta.width,
    inputHeight: meta.height,
    bboxOriginX: -(trimmed.info.trimOffsetLeft ?? 0),
    bboxOriginY: -(trimmed.info.trimOffsetTop ?? 0),
    bboxWidth: trimmed.info.width,
    bboxHeight: trimmed.info.height,
    sourceScale,
    left: modelLeftPadding,
    top: 0,
    canvasWidth: modelCanvasWidth,
    canvasHeight: modelCanvasHeight,
  });
  const faceGuard = await sharp({
    create: {
      width: guard.width,
      height: guard.height,
      channels: 3,
      background: { r: 0, g: 0, b: 0 },
    },
  }).png().toBuffer();
  const mask = await sharp(featheredMask)
    .composite([{ input: faceGuard, left: guard.left, top: guard.top }])
    .png()
    .toBuffer();

  return {
    shouldFill: true,
    padded,
    mask,
    personLayer,
    edges: geometry.edges,
    mapping,
  };
}

function computeMinimalFaceGuardRect(args: {
  face?: FaceBox;
  inputWidth: number;
  inputHeight: number;
  bboxOriginX: number;
  bboxOriginY: number;
  bboxWidth: number;
  bboxHeight: number;
  sourceScale: number;
  left: number;
  top: number;
  canvasWidth: number;
  canvasHeight: number;
}): { left: number; top: number; width: number; height: number } {
  const {
    face, inputWidth, inputHeight, bboxOriginX, bboxOriginY, bboxWidth,
    bboxHeight, sourceScale, left, top, canvasWidth, canvasHeight,
  } = args;

  let x: number;
  let y: number;
  let width: number;
  let height: number;
  if (face) {
    x = left + face.x * inputWidth * sourceScale;
    y = top + face.y * inputHeight * sourceScale;
    width = face.width * inputWidth * sourceScale;
    height = face.height * inputHeight * sourceScale;
  } else {
    x = left + bboxOriginX * sourceScale;
    y = top + bboxOriginY * sourceScale;
    width = bboxWidth * sourceScale;
    height = bboxHeight * sourceScale * 0.55;
  }

  const padTop = height * (face ? 0.9 : 0);
  const padBottom = height * (face ? 0.35 : 0);
  const padSides = width * (face ? 0.55 : 0);
  const guardLeft = Math.max(0, Math.round(x - padSides));
  const guardTop = Math.max(0, Math.round(y - padTop));
  const guardRight = Math.min(canvasWidth, Math.round(x + width + padSides));
  const guardBottom = Math.min(canvasHeight, Math.round(y + height + padBottom));
  return {
    left: guardLeft,
    top: guardTop,
    width: Math.max(1, guardRight - guardLeft),
    height: Math.max(1, guardBottom - guardTop),
  };
}

/**
 * Restore the uploaded source pixels byte-for-byte over the generated result.
 * Only pixels outside the original alpha remain model-generated.
 */
export async function restoreMinimalBodyFillSubject(
  filledCutout: Buffer,
  personLayer: Buffer,
  mapping: FillBodyMapping,
): Promise<Buffer> {
  const base = await sharp(filledCutout)
    .ensureAlpha()
    .resize(mapping.canvasWidth, mapping.canvasHeight, { fit: "fill" })
    .png()
    .toBuffer();
  const alpha = await sharp(personLayer)
    .ensureAlpha()
    .extractChannel("alpha")
    .raw()
    .toBuffer({ resolveWithObject: true });
  const knockout = Buffer.alloc(alpha.data.length * 4);
  for (let i = 0; i < alpha.data.length; i++) {
    knockout[i * 4 + 3] = alpha.data[i]! > 0 ? 255 : 0;
  }
  const knockoutPng = await sharp(knockout, {
    raw: {
      width: alpha.info.width,
      height: alpha.info.height,
      channels: 4,
    },
  }).png().toBuffer();

  return sharp(base)
    .composite([
      { input: knockoutPng, blend: "dest-out" },
      { input: personLayer, blend: "over" },
    ])
    .png()
    .toBuffer();
}

export async function padForOutpaint(
  cutoutPng: Buffer,
  options?: { face?: FaceBox }
): Promise<{ padded: Buffer; mask: Buffer; personLayer: Buffer }> {
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

  // The person on a *transparent* canvas at the exact same placement, with
  // its clean (soft) alpha intact. The fill pipeline re-mattes the whole
  // canvas after FLUX, which re-contaminates the hair edges (they were
  // flattened onto grey above) into a light halo. `restoreOriginalSubject`
  // composites this clean layer back over the re-matted result so the person
  // round-trips unchanged and only the freshly-painted body keeps the new matte.
  const personLayer = await sharp({
    create: {
      width: CANVAS_W,
      height: CANVAS_H,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([{ input: resized, left, top }])
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

  return { padded, mask, personLayer };
}

/**
 * Composite the fill pipeline's re-matted result with the *original* clean
 * person, eliminating the light hair halo.
 *
 * Why this is needed: padForOutpaint flattens the cutout onto mid-grey so
 * FLUX gets an RGB photo, then `magicCutout` (BiRefNet) re-extracts alpha over
 * the whole canvas. The person's semi-transparent hair edges — now hair·α +
 * grey·(1-α) — get re-matted into a visible grey/white fringe. FLUX only
 * legitimately paints the masked margin, so the person should round-trip
 * unchanged. We hard-knock-out the re-matted person region (any meaningful
 * alpha → erased, so even wispy strands fully suppress the contaminated
 * pixels) and lay the original clean RGBA back on top, keeping the freshly
 * painted body only where the original had no alpha.
 *
 * `personLayer` is the CANVAS_W×CANVAS_H clean person from padForOutpaint;
 * `filledCutout` is BiRefNet's output (normalised to the canvas grid here).
 */
export async function restoreOriginalSubject(
  filledCutout: Buffer,
  personLayer: Buffer,
): Promise<Buffer> {
  const base = await sharp(filledCutout)
    .ensureAlpha()
    .resize(CANVAS_W, CANVAS_H, { fit: "fill" })
    .png()
    .toBuffer();

  // Build a binary knockout layer (rgb=0, alpha carries the mask) from the
  // person's alpha. Thresholded rather than soft: a soft knockout would let
  // the re-matted grey survive at exactly the wispy edges we want to clean.
  const a = await sharp(personLayer)
    .ensureAlpha()
    .extractChannel("alpha")
    .raw()
    .toBuffer({ resolveWithObject: true });
  const knock = Buffer.alloc(a.data.length * 4);
  for (let i = 0; i < a.data.length; i++) {
    knock[i * 4 + 3] = a.data[i]! >= 8 ? 255 : 0;
  }
  const knockoutPng = await sharp(knock, {
    raw: { width: a.info.width, height: a.info.height, channels: 4 },
  })
    .png()
    .toBuffer();

  return sharp(base)
    .composite([
      // dest-out erases the re-matted person pixels (result = dest·(1-src.α)).
      { input: knockoutPng, blend: "dest-out" },
      // Lay the original clean person back with its soft alpha intact.
      { input: personLayer, blend: "over" },
    ])
    .png()
    .toBuffer();
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
