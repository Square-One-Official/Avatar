#!/usr/bin/env node
/**
 * E55.5 — importeer de Effects-stijlen uit Thierry's curatiemap in de Payload
 * CMS. Vervangt het externe seed-kit-script (_aaavatar-seed/seed-effects.mjs):
 *   - thumbnails komen uit de gecureerde `<Effect>/Thumbnail/`-map (geen
 *     nano-banana-generatie meer, dus ook géén REPLICATE_API_TOKEN nodig);
 *   - stijlreferenties komen uit `<Effect>/References/` (fallback: de
 *     kit-refs uit effects-seed.json — gecureerd, gezichts-/logo-vrij);
 *   - prompts/keys/labels/orders komen uit effects-seed.json;
 *   - assets worden genormaliseerd (refs ≤1024px, thumbs ≤800px, GIF → PNG
 *     eerste frame) vóór upload;
 *   - een media-URL-probe bewaakt dat de admin directe Supabase-URLs uitgeeft
 *     (837498f) — proxy-URLs zouden anonieme app-loads breken (MFA-401).
 *
 * Standaard een DRY-RUN (map-validatie + gap-rapport); schrijven vereist
 * expliciet `--apply`.
 *
 * Gebruik:
 *   node scripts/import-effects.mjs                        # dry-run, hele set
 *   node scripts/import-effects.mjs --only balloon,windy   # subset
 *   node scripts/import-effects.mjs --apply                # echte run
 *   node scripts/import-effects.mjs --apply --force        # ook bestaande keys bijwerken
 *   node scripts/import-effects.mjs --deactivate clay,wood,3d,scribble --apply
 *
 * Env (alleen nodig voor --apply/--deactivate en de bestaand-check):
 *   PAYLOAD_API_URL   bv. https://admin.aaavatar.nl
 *   PAYLOAD_API_KEY   Payload users API-key (omzeilt de MFA-middleware)
 *
 * Idempotent: bestaande keys worden overgeslagen tenzij --force; her-runnen na
 * een prompt-tweak (55.7-bakeoff) is dus veilig.
 */

import { readdir, readFile, stat } from "node:fs/promises";
import { join } from "node:path";
import sharp from "sharp";

const DEFAULT_SOURCE =
  "/Users/thierry/Documents/Aaavatar_ChatGPT Images 2.0 Edit_2026-05-03_08-35-45/Effects";

const args = process.argv.slice(2);
const APPLY = args.includes("--apply");
const FORCE = args.includes("--force");
const SKIP_PROBE = args.includes("--skip-url-probe");
const argValue = (flag) => {
  const i = args.indexOf(flag);
  return i >= 0 && args[i + 1] && !args[i + 1].startsWith("--") ? args[i + 1] : null;
};
const SOURCE = argValue("--source") ?? DEFAULT_SOURCE;
const SEED_PATH = argValue("--seed") ?? join(SOURCE, "_aaavatar-seed", "effects-seed.json");
const ONLY = argValue("--only")?.split(",").map((s) => s.trim()) ?? null;
const DEACTIVATE = argValue("--deactivate")?.split(",").map((s) => s.trim()) ?? null;

const PAYLOAD_BASE = (process.env.PAYLOAD_API_URL ?? "")
  .trim()
  .replace(/\/+$/, "")
  .replace(/\/api$/, "");
const PAYLOAD_KEY = process.env.PAYLOAD_API_KEY ?? "";
const HAS_API = Boolean(PAYLOAD_BASE && PAYLOAD_KEY);

if ((APPLY || DEACTIVATE) && !HAS_API) {
  console.error("--apply/--deactivate vereisen PAYLOAD_API_URL en PAYLOAD_API_KEY.");
  process.exit(1);
}

const authHeaders = { Authorization: `users API-Key ${PAYLOAD_KEY}` };

// De vorm die de app-keten verwacht: directe publieke Supabase-URL (regex van
// backend/lib/payload.ts thumbnailVariant). Een Payload-proxy-URL
// (admin.aaavatar.nl/api/media/file/…) zit achter de MFA-middleware → 401
// voor anonieme app-loads én geen CDN-verkleining.
const DIRECT_URL_RE = /^https?:\/\/[^/]+\/storage\/v1\/object\/public\//;

const IMAGE_EXT = /\.(jpe?g|png|webp|gif)$/i;
const MAX_REF_ROWS = 4; // schema-cap op styleReferences (backend stuurt max 3)

/**
 * E55.7-bakeoff (besluit Thierry 2026-08-03): deze stijlen seeden ALTIJD
 * prompt-only — de flowers-referenties (gerbera's over een gezicht) triggeren
 * gpt-image-2's moderatie (2/2 geweigerd op het vrouwenportret; zonder refs
 * slaagt dezelfde stijl glansrijk). Hard in de importer gebakken zodat een
 * her-run de refs niet per ongeluk terugkoppelt.
 */
const PROMPT_ONLY_KEYS = new Set(["flowers"]);
const REF_MAX_EDGE = 1024; // zelfde maat als fetchStyleReferences' transform
const THUMB_MAX_EDGE = 800; // kaart toont 320px-variant; 800 dekt @2x ruim

async function payloadGet(path) {
  const res = await fetch(`${PAYLOAD_BASE}/api${path}`, { headers: authHeaders });
  if (!res.ok) throw new Error(`GET ${path} -> ${res.status}: ${await res.text()}`);
  return res.json();
}

async function payloadJson(method, path, body) {
  const res = await fetch(`${PAYLOAD_BASE}/api${path}`, {
    method,
    headers: { ...authHeaders, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}: ${await res.text()}`);
  return res.json();
}

async function uploadMedia(bytes, filename, alt, mime) {
  const form = new FormData();
  form.append("file", new Blob([bytes], { type: mime }), filename);
  form.append("_payload", JSON.stringify({ alt }));
  const res = await fetch(`${PAYLOAD_BASE}/api/media`, {
    method: "POST",
    headers: authHeaders,
    body: form,
  });
  if (!res.ok) throw new Error(`upload ${filename} -> ${res.status}: ${await res.text()}`);
  const json = await res.json();
  const doc = json.doc ?? json;
  if (!doc.id) throw new Error(`upload ${filename}: geen doc id in response`);
  return doc;
}

/** Normaliseer een referentie/thumbnail: resize + herformatteer. */
async function normalizeImage(bytes, { maxEdge, preferPng }) {
  const img = sharp(bytes, { animated: false }); // GIF → eerste frame
  const meta = await img.metadata();
  const resized = img.resize({
    width: (meta.width ?? 0) >= (meta.height ?? 0) ? maxEdge : undefined,
    height: (meta.height ?? 0) > (meta.width ?? 0) ? maxEdge : undefined,
    withoutEnlargement: true,
  });
  if (preferPng || meta.hasAlpha) {
    return { bytes: await resized.png().toBuffer(), ext: "png", mime: "image/png" };
  }
  return { bytes: await resized.jpeg({ quality: 90 }).toBuffer(), ext: "jpg", mime: "image/jpeg" };
}

/** Eerste submap die met "ref" begint (References/Reference/Refeferences/…). */
async function refSubdir(folderPath) {
  try {
    const entries = await readdir(folderPath, { withFileTypes: true });
    const hit = entries.find((e) => e.isDirectory() && /^ref/i.test(e.name));
    return hit ? join(folderPath, hit.name) : join(folderPath, "References");
  } catch {
    return join(folderPath, "References");
  }
}

async function listImages(dir) {
  if (!dir) return null;
  try {
    const entries = await readdir(dir);
    const files = [];
    for (const name of entries.sort()) {
      if (!IMAGE_EXT.test(name)) continue;
      const full = join(dir, name);
      if ((await stat(full)).isFile()) files.push({ name, path: full });
    }
    return files;
  } catch {
    return null; // map bestaat niet
  }
}

/** Zoek de effect-map: label, key of eerste label-woord (case-insensitive). */
function resolveFolder(effect, dirNames) {
  const candidates = [effect.label, effect.key, effect.label.split(" ")[0]]
    .map((c) => c.toLowerCase());
  for (const dir of dirNames) {
    if (candidates.includes(dir.toLowerCase())) return dir;
  }
  return null;
}

// --- Deactivate-modus -------------------------------------------------------

if (DEACTIVATE) {
  for (const key of DEACTIVATE) {
    const existing = await payloadGet(
      `/effects?where[key][equals]=${encodeURIComponent(key)}&limit=1`,
    );
    const doc = existing.docs?.[0];
    if (!doc) {
      console.log(`deactivate ${key}: niet gevonden — overgeslagen`);
      continue;
    }
    if (doc.active === false) {
      console.log(`deactivate ${key}: stond al op inactief (id ${doc.id})`);
      continue;
    }
    if (!APPLY) {
      console.log(`deactivate ${key}: zou active=false zetten (id ${doc.id}) — draai met --apply`);
      continue;
    }
    await payloadJson("PATCH", `/effects/${doc.id}`, { active: false });
    console.log(`deactivate ${key}: active=false gezet (id ${doc.id})`);
  }
  process.exit(0);
}

// --- Import-modus -----------------------------------------------------------

const seed = JSON.parse(await readFile(SEED_PATH, "utf8"));
const seedDir = join(SEED_PATH, "..");
const dirNames = (await readdir(SOURCE, { withFileTypes: true }))
  .filter((d) => d.isDirectory() && !d.name.startsWith("_") && !d.name.startsWith("."))
  .map((d) => d.name);

console.log(`Bron: ${SOURCE}`);
console.log(`Seed: ${SEED_PATH} (${seed.effects.length} presets)`);
console.log(APPLY ? "Modus: APPLY (schrijft naar het CMS)" : "Modus: dry-run (geen writes)");
if (!HAS_API) console.log("Geen PAYLOAD-env — bestaand-check overgeslagen.");

// Media-URL-probe vóór enige upload (E54-les: nieuwe admin-build kan
// proxy-URLs uitgeven; dan is elke upload hierna onbruikbaar voor de app).
if (APPLY && !SKIP_PROBE) {
  const px = await sharp({
    create: { width: 1, height: 1, channels: 3, background: { r: 200, g: 200, b: 200 } },
  })
    .png()
    .toBuffer();
  const probe = await uploadMedia(px, "effect-url-probe.png", "URL-vorm probe", "image/png");
  const ok = DIRECT_URL_RE.test(probe.url ?? "");
  try {
    await payloadJson("DELETE", `/media/${probe.id}`);
  } catch {
    console.warn(`  (probe media ${probe.id} kon niet verwijderd worden — handmatig opruimen)`);
  }
  if (!ok) {
    console.error(
      `URL-PROBE FAALT: media-URL is "${probe.url}" — geen directe Supabase-vorm.\n` +
        `De admin-build mist de generateFileURL-fix (837498f / E55.5). Deploy de admin\n` +
        `met die fix vóór het seeden; zie admin/RUNBOOK-effects.md.`,
    );
    process.exit(1);
  }
  console.log("URL-probe OK: admin geeft directe Supabase-URLs uit.");
}

let skipped = 0;
for (const effect of seed.effects) {
  if (ONLY && !ONLY.includes(effect.key)) continue;
  console.log(`\n=== ${effect.key} (${effect.label}) ===`);

  const problems = [];
  const notes = [];

  // 1. Map + assets vinden.
  const folder = resolveFolder(effect, dirNames);
  if (!folder) notes.push(`geen curatiemap gevonden (kandidaten: ${effect.label}/${effect.key})`);
  const folderPath = folder ? join(SOURCE, folder) : null;

  // Ref-submap: de curatiemap is met de hand gegroeid — tolereer varianten
  // ("References", "Reference", "Refeferences", "Refs") door de eerste
  // submap te pakken die met "ref" begint (case-insensitive).
  const folderRefs = folderPath ? await listImages(await refSubdir(folderPath)) : null;
  const folderThumbs = folderPath ? await listImages(join(folderPath, "Thumbnail")) : null;
  const loose = folderPath ? (await listImages(folderPath)) ?? [] : [];
  if (loose.length > 0) {
    notes.push(
      `${loose.length} losse bestanden in de map-root (worden GENEGEERD — verplaats naar References/ of Thumbnail/): ${loose.map((f) => f.name).join(", ")}`,
    );
  }

  // Referenties: curatiemap eerst; anders de gecureerde kit-refs.
  // Prompt-only-stijlen (E55.7-moderatiebesluit) krijgen er bewust géén.
  let refFiles;
  let refSourceLabel;
  if (PROMPT_ONLY_KEYS.has(effect.key)) {
    refFiles = [];
    refSourceLabel = "prompt-only (E55.7-besluit — refs triggeren moderatie)";
  } else if (folderRefs && folderRefs.length > 0) {
    refFiles = folderRefs;
    refSourceLabel = `References/ (${folder})`;
  } else {
    refFiles = (effect.refs ?? []).map((name) => ({ name, path: join(seedDir, "refs", name) }));
    refSourceLabel = "kit-refs (fallback — References/ leeg of afwezig)";
    if (folderRefs !== null && folderRefs.length === 0) notes.push("References/ bestaat maar is leeg");
  }
  if (refFiles.length === 0 && !PROMPT_ONLY_KEYS.has(effect.key)) {
    problems.push("geen referenties (map noch kit)");
  }
  if (refFiles.length > MAX_REF_ROWS) {
    notes.push(
      `${refFiles.length} refs > schema-cap ${MAX_REF_ROWS} — gedropt: ${refFiles
        .slice(MAX_REF_ROWS)
        .map((f) => f.name)
        .join(", ")}`,
    );
    refFiles = refFiles.slice(0, MAX_REF_ROWS);
  }
  for (const f of refFiles.filter((f) => /\.gif$/i.test(f.name))) {
    notes.push(`${f.name} is een GIF — eerste frame wordt als PNG geüpload; check het resultaat`);
  }

  // Thumbnail: uit de curatiemap. Ontbreekt 'ie (besluit Thierry 2026-08-03:
  // nieuwe stijlen mogen vóór hun thumbnail live), dan seeden we zónder —
  // de app toont het sparkles-placeholder tot een --force-her-run 'm koppelt.
  const thumbFile = folderThumbs?.[0] ?? null;
  if (!thumbFile) {
    notes.push("geen thumbnail — app toont sparkles-placeholder; koppel later via --force of de admin-UI");
  }
  if ((folderThumbs?.length ?? 0) > 1) {
    notes.push(`meerdere thumbnails — eerste gekozen: ${thumbFile.name}`);
  }

  // Prompt-sanity: hoort op de identity-clausule te eindigen.
  if (!/identifiable\.?\s*$/.test(effect.prompt)) {
    notes.push("prompt eindigt NIET op de identity-clausule — bewust?");
  }

  // 2. Bestaand-check.
  let existingDoc = null;
  if (HAS_API) {
    const existing = await payloadGet(
      `/effects?where[key][equals]=${encodeURIComponent(effect.key)}&limit=1`,
    );
    existingDoc = existing.docs?.[0] ?? null;
  }

  // 3. Rapport.
  console.log(`  map: ${folder ?? "—"} · refs: ${refFiles.length} uit ${refSourceLabel}`);
  console.log(`  thumbnail: ${thumbFile ? `${thumbFile.name}` : "ONTBREEKT"}`);
  if (HAS_API) {
    console.log(
      `  CMS: ${existingDoc ? `bestaat (id ${existingDoc.id})${FORCE ? " → update" : " → skip (--force voor update)"}` : "nieuw → create"}`,
    );
  }
  for (const n of notes) console.log(`  ⚠ ${n}`);
  for (const p of problems) console.log(`  ✗ ${p}`);

  if (problems.length > 0) {
    console.log("  → overgeslagen (los de ✗-punten op)");
    skipped++;
    continue;
  }
  if (!APPLY) continue;
  if (existingDoc && !FORCE) continue;

  // 4. Uploaden + upsert.
  const refIds = [];
  for (const ref of refFiles) {
    const raw = await readFile(ref.path);
    const norm = await normalizeImage(raw, { maxEdge: REF_MAX_EDGE, preferPng: false });
    const base = ref.name.replace(IMAGE_EXT, "");
    const doc = await uploadMedia(
      norm.bytes,
      `effect-${effect.key}-${base}.${norm.ext}`,
      `${effect.label} style reference`,
      norm.mime,
    );
    refIds.push(doc.id);
    console.log(`  ref ${ref.name} -> media ${doc.id}`);
  }

  let thumbId = null;
  if (thumbFile) {
    const thumbRaw = await readFile(thumbFile.path);
    const thumbNorm = await normalizeImage(thumbRaw, { maxEdge: THUMB_MAX_EDGE, preferPng: true });
    const thumbDoc = await uploadMedia(
      thumbNorm.bytes,
      `effect-${effect.key}-thumbnail.${thumbNorm.ext}`,
      `${effect.label} effect thumbnail`,
      thumbNorm.mime,
    );
    thumbId = thumbDoc.id;
    console.log(`  thumbnail -> media ${thumbId}`);
  } else {
    console.log("  thumbnail: overgeslagen (app-placeholder tot de curatiemap er een heeft)");
  }

  const body = {
    key: effect.key,
    label: effect.label,
    prompt: effect.prompt,
    order: effect.order,
    active: true,
    // Zonder thumbnail het veld niet meesturen: een --force-her-run zonder
    // nieuwe thumbnail mag een eerder gekoppelde ook niet WISSEN.
    ...(thumbId ? { thumbnail: thumbId } : {}),
    styleReferences: refIds.map((id) => ({ image: id })),
  };
  const result = existingDoc
    ? await payloadJson("PATCH", `/effects/${existingDoc.id}`, body)
    : await payloadJson("POST", "/effects", body);
  const doc = result.doc ?? result;
  console.log(`  ${existingDoc ? "bijgewerkt" : "aangemaakt"}: effect ${doc.id ?? "(ok)"}`);
}

console.log(
  `\nKlaar.${skipped ? ` ${skipped} preset(s) overgeslagen wegens ontbrekende assets.` : ""}` +
    (APPLY
      ? "\nVerifieer: GET https://api.aaavatar.nl/v1/effects (±5 min CDN-cache) — verwacht" +
        "\n/render/image/-thumbnails. Oude stijlen uitzetten: --deactivate clay,wood,3d,scribble --apply"
      : "\nDraai met --apply om te schrijven."),
);
