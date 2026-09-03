// E55.7 bakeoff-driver: gpt-image (default 2.0) × {quality high|medium} ×
// {refs aan|uit} op de zes Styles-2.0-presets, door de ECHTE productie-
// pipeline als directe lib-calls (capLongEdge → flattenOnGrey → padToAspect →
// cropBackFromPad rond stylizeEdit) — callshape 1-op-1 met /v1/stylize incl.
// IDENTITY-prompt uit effects-seed.json, STYLE_REFERENCE_CLAUSE (refs-arm) en
// FRAMING_CLAUSE. Geen HTTP/auth/credits; wel een eigen REPLICATE_API_TOKEN.
//
// Identity-vergelijking 2.0 vs 1.5 (2.0 dropte input_fidelity): draai twee
// keer met verschillende --model en leg de contactsheets naast elkaar.
//
// Draai vanuit backend/ (E41.4-patroon):
//
//   REPLICATE_API_TOKEN=… npx tsx scripts/effects-bakeoff.ts <portraitsDir> <outDir> \
//     [--model openai/gpt-image-1.5] [--styles balloon,windy] \
//     [--arms high-refs,high-norefs,medium-refs] [--spacing 11]
//
// Portretten: PNG's in <portraitsDir> (E09-set: p1-man-beard.png etc. in
// ~/Documents/Claude/Projects/Aaavatar/e09-bakeoff/inputs). Default pakt
// p1-man-beard + p3-woman-curly (de E54.2-portretten).
//
// Replicate-regel (memory: <$5 saldo = 6 predictions/min): calls strikt
// sequentieel met 11s spacing — NIET paralleliseren.
//
// Output: <outDir>/<style>-<portret>-<arm>.png + results.json (latency,
// dims, ratio-contract-check) + index.html contact-sheet voor de review.
import { mkdirSync, readdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import sharp from "sharp";
import { GPT_IMAGE_ASPECTS } from "../lib/aspects.js";
import {
  capLongEdge,
  cropBackFromPad,
  flattenOnGrey,
  nearestFixedAspect,
  padToAspect,
} from "../lib/image.js";
import { modelFixedAspects } from "../lib/models.js";
import { stylizeEdit } from "../lib/replicate.js";
import { composeEffectPrompt } from "../lib/stylizePrompts.js";

const SEED_DIR =
  "/Users/thierry/Documents/Aaavatar_ChatGPT Images 2.0 Edit_2026-05-03_08-35-45/Effects";
const SEED_JSON = join(SEED_DIR, "_aaavatar-seed", "effects-seed.json");
const DEFAULT_PORTRAITS = ["p1-man-beard", "p3-woman-curly"];
const ALL_ARMS = ["high-refs", "high-norefs", "medium-refs", "medium-norefs"] as const;
type Arm = (typeof ALL_ARMS)[number];

const args = process.argv.slice(2);
const positional = args.filter((a) => !a.startsWith("--"));
const argValue = (flag: string) => {
  const i = args.indexOf(flag);
  return i >= 0 && args[i + 1] ? args[i + 1] : null;
};
const [portraitsDir, outDir] = positional;
if (!portraitsDir || !outDir || !process.env.REPLICATE_API_TOKEN) {
  console.error(
    "usage: REPLICATE_API_TOKEN=… npx tsx scripts/effects-bakeoff.ts <portraitsDir> <outDir> [--styles a,b] [--arms high-refs,…] [--spacing 11]",
  );
  process.exit(1);
}
const ONLY_STYLES = argValue("--styles")?.split(",") ?? null;
const ARMS = (argValue("--arms")?.split(",") as Arm[] | undefined) ?? [
  "high-refs",
  "high-norefs",
  "medium-refs",
];
const SPACING_S = Number(argValue("--spacing") ?? 11);
const MODEL = argValue("--model") ?? "openai/gpt-image-2";
// Meet-timeout (s): ruim boven het 80s-prod-budget zodat trage runs hun échte
// duur laten zien i.p.v. als timeout te sneuvelen — dat getal ís de meting.
const TIMEOUT_S = Number(argValue("--timeout") ?? 240);
// Callshape-parity: pad naar de ratio-set van het gekozen model (registry).
const MODEL_ASPECTS = modelFixedAspects(MODEL) ?? GPT_IMAGE_ASPECTS;
mkdirSync(outDir, { recursive: true });

type SeedEffect = { key: string; label: string; prompt: string; refs: string[] };
const seed = JSON.parse(readFileSync(SEED_JSON, "utf8")) as { effects: SeedEffect[] };
const styles = seed.effects.filter((e) => !ONLY_STYLES || ONLY_STYLES.includes(e.key));

const portraitNames = (() => {
  const available = readdirSync(portraitsDir).filter((f) => f.endsWith(".png"));
  const wanted = DEFAULT_PORTRAITS.filter((p) => available.includes(`${p}.png`));
  return wanted.length > 0 ? wanted : available.slice(0, 2).map((f) => f.replace(/\.png$/, ""));
})();

/** Referenties zoals de importer ze zou seeden: curatiemap eerst, kit-refs
 *  als fallback; genormaliseerd naar ≤1024 px (= fetchStyleReferences' maat),
 *  cap 3 (= STYLE_REF_MAX). */
async function refDataUrls(effect: SeedEffect): Promise<string[]> {
  const candidates = [effect.label, effect.key, effect.label.split(" ")[0]];
  let files: string[] = [];
  for (const c of candidates) {
    const dir = join(SEED_DIR, c, "References");
    if (existsSync(dir)) {
      files = readdirSync(dir)
        .filter((f) => /\.(jpe?g|png|webp)$/i.test(f))
        .sort()
        .map((f) => join(dir, f));
      if (files.length > 0) break;
    }
  }
  if (files.length === 0) {
    files = effect.refs.map((r) => join(SEED_DIR, "_aaavatar-seed", "refs", r));
  }
  const urls: string[] = [];
  for (const file of files.slice(0, 3)) {
    const raw = readFileSync(file);
    const jpg = await sharp(raw).resize({ width: 1024, height: 1024, fit: "inside", withoutEnlargement: true }).jpeg({ quality: 85 }).toBuffer();
    urls.push(`data:image/jpeg;base64,${jpg.toString("base64")}`);
  }
  return urls;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let lastDispatch = 0;
async function throttle() {
  const wait = lastDispatch + SPACING_S * 1000 - Date.now();
  if (wait > 0) await sleep(wait);
  lastDispatch = Date.now();
}

type RunResult = {
  style: string;
  portrait: string;
  arm: Arm;
  ok: boolean;
  ms?: number;
  inputDims?: string;
  outputDims?: string;
  ratioContractOk?: boolean;
  refs?: number;
  error?: string;
  file?: string;
};
const results: RunResult[] = [];

console.log(
  `Matrix: ${styles.length} stijlen × ${portraitNames.length} portretten × ${ARMS.length} armen = ${styles.length * portraitNames.length * ARMS.length} runs (spacing ${SPACING_S}s)`,
);

for (const portrait of portraitNames) {
  const rawPng = readFileSync(join(portraitsDir, `${portrait}.png`));
  // Productie-pipeline: cap → flatten → pad (gpt-image is ratio-vast).
  const capped = await capLongEdge(rawPng, 2048);
  const flattened = await flattenOnGrey(capped);
  const meta = await sharp(flattened).metadata();
  const inputW = meta.width ?? 0;
  const inputH = meta.height ?? 0;
  const target = nearestFixedAspect(inputW, inputH, MODEL_ASPECTS);
  const pad = await padToAspect(flattened, target.ratio);
  const inputDataUrl = `data:image/png;base64,${pad.padded.toString("base64")}`;
  const srcRatio = inputW / inputH;

  for (const style of styles) {
    const allRefs = await refDataUrls(style);
    for (const arm of ARMS) {
      const useRefs = arm.endsWith("-refs") && !arm.includes("norefs");
      const quality = arm.startsWith("high") ? ("high" as const) : ("medium" as const);
      const refs = useRefs ? allRefs : [];
      // Prompt exact als /v1/stylize voor Effects: CMS-prompt (eindigt op de
      // identity-clausule) + rolclausule bij refs + framing (preserve_framing
      // staat in productie hard aan voor Effects).
      const prompt = composeEffectPrompt({
        basePrompt: style.prompt,
        styleKey: style.key,
        hasStyleReferences: refs.length > 0,
        preserveFraming: true,
      });

      const name = `${style.key}-${portrait}-${arm}`;
      const t0 = Date.now();
      try {
        await throttle();
        const url = await stylizeEdit({
          imageDataUrl: inputDataUrl,
          prompt,
          styleReferenceDataUrls: refs,
          width: pad.canvasW,
          height: pad.canvasH,
          model: MODEL,
          gptQuality: quality,
          timeoutMs: TIMEOUT_S * 1000,
        });
        const dl = await fetch(url);
        if (!dl.ok) throw new Error(`result fetch ${dl.status}`);
        let out: Buffer = Buffer.from(await dl.arrayBuffer());
        out = await cropBackFromPad(out, pad);
        const ms = Date.now() - t0;
        const outMeta = await sharp(out).metadata();
        const outRatio = (outMeta.width ?? 0) / (outMeta.height ?? 1);
        const contractOk = Math.abs(outRatio - srcRatio) / srcRatio < 0.01;
        const file = `${name}.png`;
        writeFileSync(join(outDir, file), out);
        results.push({
          style: style.key, portrait, arm, ok: true, ms,
          inputDims: `${inputW}x${inputH}`,
          outputDims: `${outMeta.width}x${outMeta.height}`,
          ratioContractOk: contractOk, refs: refs.length, file,
        });
        console.log(
          `OK  ${name}: ${outMeta.width}×${outMeta.height} in ${(ms / 1000).toFixed(1)}s` +
            (contractOk ? "" : "  ⚠ RATIO-CONTRACT GESCHONDEN"),
        );
      } catch (err) {
        // Zelfde privacy-regel als het endpoint: alleen de message loggen (het
        // Replicate-error-object bevat de auth-header).
        const msg = err instanceof Error ? err.message : String(err);
        results.push({ style: style.key, portrait, arm, ok: false, error: msg });
        console.error(`ERR ${name}: ${msg}`);
      }
    }
  }
}

writeFileSync(
  join(outDir, "results.json"),
  JSON.stringify({ model: MODEL, results }, null, 2),
);

// Contact-sheet voor de menselijke review (stijltrouw + identiteit).
const cell = (r: RunResult) =>
  r.ok
    ? `<figure><img src="${r.file}" loading="lazy"><figcaption>${r.style} · ${r.portrait}<br>${r.arm} · ${((r.ms ?? 0) / 1000).toFixed(1)}s · refs ${r.refs}${r.ratioContractOk ? "" : " · ⚠ratio"}</figcaption></figure>`
    : `<figure class="err"><figcaption>${r.style} · ${r.portrait}<br>${r.arm} · FOUT: ${r.error}</figcaption></figure>`;
writeFileSync(
  join(outDir, "index.html"),
  `<!doctype html><meta charset="utf-8"><title>E55.7 effects-bakeoff</title>
<style>body{font:13px -apple-system,sans-serif;background:#111;color:#eee;margin:20px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:14px}
figure{margin:0}img{width:100%;border-radius:8px}figcaption{padding:6px 2px;color:#bbb}
.err figcaption{color:#f66}</style>
<h1>E55.7 — ${MODEL} bakeoff (${new Date().toISOString().slice(0, 10)})</h1>
<p>${results.filter((r) => r.ok).length}/${results.length} runs OK · beoordeel per arm: stijltrouw t.o.v. de referenties, identiteitsbehoud, framing.</p>
<div class="grid">${results.map(cell).join("\n")}</div>`,
);

const ok = results.filter((r) => r.ok);
const p = (arr: number[], q: number) =>
  arr.length ? arr.sort((a, b) => a - b)[Math.min(arr.length - 1, Math.floor(q * arr.length))] : 0;
for (const quality of ["high", "medium"]) {
  const times = ok.filter((r) => r.arm.startsWith(quality)).map((r) => r.ms ?? 0);
  if (times.length) {
    console.log(
      `${quality}: n=${times.length} p50=${(p(times, 0.5) / 1000).toFixed(1)}s p95=${(p(times, 0.95) / 1000).toFixed(1)}s (timeout-budget 80s)`,
    );
  }
}
const broken = ok.filter((r) => !r.ratioContractOk);
console.log(
  `Ratio-contract: ${ok.length - broken.length}/${ok.length} OK${broken.length ? ` — GESCHONDEN: ${broken.map((r) => `${r.style}-${r.portrait}-${r.arm}`).join(", ")}` : ""}`,
);
console.log(`\nReview: open ${join(outDir, "index.html")} — prijzen per kwaliteitstier: zie replicate.com/openai/gpt-image-1.5 (pricing in de model-HTML).`);
