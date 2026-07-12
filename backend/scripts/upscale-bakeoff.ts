// E41.4 bakeoff-driver: 4 upscale-armen × 5 E09-portretten door de ECHTE
// endpoint-pipeline (bleedFlatten → Replicate-upscale → reapplyAlpha), maar
// dan als directe lib-calls — geen HTTP/auth/deployment-protection nodig en
// géén credits (eigen REPLICATE_API_TOKEN). Draai vanuit backend/:
//
//   REPLICATE_API_TOKEN=… npx tsx scripts/upscale-bakeoff.ts <inputsDir> <outDir>
//
// Replicate-regel (memory: <$5 saldo = 6 predictions/min): calls strikt
// sequentieel met 11s spacing — NIET paralleliseren.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import sharp from "sharp";
import { bleedFlatten, reapplyAlpha } from "../lib/image.js";
import { upscale } from "../lib/replicate.js";
import { MODEL_REGISTRY } from "../lib/models.js";

const ARMS = ["topaz", "google-upscaler", "crystal-upscaler", "real-esrgan"] as const;
const PORTRAITS = [
  "p1-man-beard",
  "p2-man-longhair",
  "p3-woman-curly",
  "p4-woman-smile",
  "p5-man-headset",
];

const [inputsDir, outDir] = process.argv.slice(2);
if (!inputsDir || !outDir || !process.env.REPLICATE_API_TOKEN) {
  console.error("usage: REPLICATE_API_TOKEN=… npx tsx scripts/upscale-bakeoff.ts <inputsDir> <outDir>");
  process.exit(1);
}
mkdirSync(outDir, { recursive: true });

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let lastDispatch = 0;
async function throttle() {
  const wait = lastDispatch + 11_000 - Date.now();
  if (wait > 0) await sleep(wait);
  lastDispatch = Date.now();
}

for (const portrait of PORTRAITS) {
  const inputPng = readFileSync(`${inputsDir}/${portrait}.png`);
  const flattened = await bleedFlatten(inputPng);
  writeFileSync(`${outDir}/${portrait}-flattened.png`, flattened);
  const dataUrl = `data:image/png;base64,${flattened.toString("base64")}`;
  for (const arm of ARMS) {
    const ref = MODEL_REGISTRY.upscale.models[arm].ref;
    const t = Date.now();
    try {
      await throttle();
      const url = await upscale({ imageDataUrl: dataUrl, model: ref });
      const dl = await fetch(url);
      if (!dl.ok) throw new Error(`result fetch ${dl.status}`);
      const rgb = Buffer.from(await dl.arrayBuffer());
      const cutout = await reapplyAlpha(rgb, inputPng);
      writeFileSync(`${outDir}/${portrait}-${arm}.png`, cutout);
      const m = await sharp(cutout).metadata();
      console.log(`OK  ${portrait} × ${arm}: ${m.width}×${m.height} in ${((Date.now() - t) / 1000).toFixed(1)}s`);
    } catch (err) {
      // Zelfde privacy-regel als het endpoint: alleen de message loggen (het
      // Replicate-error-object bevat de auth-header).
      const msg = err instanceof Error ? err.message : String(err);
      console.log(`ERR ${portrait} × ${arm}: ${msg}`);
    }
  }
}
console.log("bakeoff done");
