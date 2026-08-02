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

/** Vaste ratio-set van gpt-image (schema her-geverifieerd 2026-08-02). */
export type FixedAspectKey = "1:1" | "3:2" | "2:3";

export interface FixedAspect {
  key: FixedAspectKey;
  ratio: number;
}

export const GPT_IMAGE_ASPECTS: FixedAspect[] = [
  { key: "1:1", ratio: 1 },
  { key: "3:2", ratio: 1.5 },
  { key: "2:3", ratio: 2 / 3 },
];

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
