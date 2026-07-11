// E01.10 smoke-driver: draai met `npx tsx scripts/models-smoke.ts` vanuit
// backend/. Puur lokaal — geen netwerk, geen Replicate-calls.
import assert from "node:assert";
import {
  MODEL_REGISTRY,
  UnknownModelOverrideError,
  defaultModelRef,
  resolveModelOverride,
} from "../lib/models.js";

assert.equal(resolveModelOverride("cutout", undefined, true), null);
assert.equal(resolveModelOverride("cutout", "", true), null);
// niet-dev: override genegeerd, ook met geldige key
assert.equal(resolveModelOverride("cutout", "birefnet", false), null);
// dev + whitelisted key → ref
assert.match(resolveModelOverride("cutout", "birefnet", true)!, /^men1scus\/birefnet:/);
// dev + onbekende key → harde fout (geen stille fallback)
assert.throws(() => resolveModelOverride("cutout", "evil-model", true), UnknownModelOverrideError);
// niet-dev + onbekende key → genegeerd, geen oracle
assert.equal(resolveModelOverride("cutout", "evil-model", false), null);
assert.equal(defaultModelRef("fill_body"), "black-forest-labs/flux-fill-pro");
// E09.1: de drie bakeoff-armen zijn whitelisted voor dev-overrides
assert.equal(resolveModelOverride("stylize", "nano-banana", true), "google/nano-banana");
assert.equal(resolveModelOverride("stylize", "flux-2-pro", true), "black-forest-labs/flux-2-pro");
assert.equal(resolveModelOverride("stylize", "gpt-image-1.5", true), "openai/gpt-image-1.5");
assert.equal(resolveModelOverride("stylize", "gpt-image-1.5", false), null);
// E32.1: de Seedream face-bakeoff-arm is whitelisted voor dev-overrides
assert.equal(resolveModelOverride("stylize", "seedream", true), "bytedance/seedream-4");
assert.equal(resolveModelOverride("stylize", "seedream", false), null);
assert.ok(
  (Object.keys(MODEL_REGISTRY) as Array<keyof typeof MODEL_REGISTRY>).every((f) => {
    const r = MODEL_REGISTRY[f];
    return r.requiresCloud && r.credits >= 1 && !!r.models[r.defaultModel];
  }),
);
// E41.3 (audit D8): community-modellen MOETEN op een 64-hex versie-hash gepind
// zijn — een unversioned community-slug kan op replicate.run 404'en. Officiële
// slugs (google/, openai/, black-forest-labs/, bytedance/, topazlabs/) mogen
// unversioned.
{
  const OFFICIAL_OWNERS = ["google", "openai", "black-forest-labs", "bytedance", "topazlabs"];
  // E41.4: crystal-upscaler staat 422 "Invalid version or not permitted" op
  // élke versioned run (de E41.3-hash wás de latest) — dit model kan alleen
  // unversioned. Bewuste, per-ref uitzondering; geen derde toevoegen zonder
  // hetzelfde 422-bewijs.
  const UNVERSIONED_EXCEPTIONS = new Set(["philz1337x/crystal-upscaler"]);
  const PINNED = /^[a-z0-9_-]+\/[a-z0-9_.-]+:[a-f0-9]{64}$/;
  for (const f of Object.keys(MODEL_REGISTRY) as Array<keyof typeof MODEL_REGISTRY>) {
    for (const [key, entry] of Object.entries(MODEL_REGISTRY[f].models)) {
      const owner = entry.ref.split("/")[0];
      if (OFFICIAL_OWNERS.includes(owner)) continue;
      if (UNVERSIONED_EXCEPTIONS.has(entry.ref)) continue;
      assert.match(
        entry.ref,
        PINNED,
        `community-model ${f}/${key} (${entry.ref}) mist een gepinde versie-hash`,
      );
    }
  }
  // De Boost-default: topaz — bakeoff-winnaar E41.4 (2026-07-03). Officiële
  // owner, dus bewust unversioned (geen pin-guard van toepassing).
  assert.equal(defaultModelRef("upscale"), "topazlabs/image-upscale");
  // E41.4-bakeoff-armen whitelisted voor dev-overrides; prefixes intact voor
  // upscaleInputFor (lib/replicate.ts matcht op het slug-prefix).
  assert.equal(resolveModelOverride("upscale", "topaz", true), "topazlabs/image-upscale");
  assert.equal(resolveModelOverride("upscale", "google-upscaler", true), "google/upscaler");
  assert.equal(
    resolveModelOverride("upscale", "crystal-upscaler", true),
    "philz1337x/crystal-upscaler",
  );
  assert.equal(resolveModelOverride("upscale", "topaz", false), null);
}
console.log("models.ts smoke OK");
