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
// slugs (google/, openai/, black-forest-labs/, bytedance/) mogen unversioned.
{
  const OFFICIAL_OWNERS = ["google", "openai", "black-forest-labs", "bytedance"];
  const PINNED = /^[a-z0-9_-]+\/[a-z0-9_.-]+:[a-f0-9]{64}$/;
  for (const f of Object.keys(MODEL_REGISTRY) as Array<keyof typeof MODEL_REGISTRY>) {
    for (const [key, entry] of Object.entries(MODEL_REGISTRY[f].models)) {
      const owner = entry.ref.split("/")[0];
      if (OFFICIAL_OWNERS.includes(owner)) continue;
      assert.match(
        entry.ref,
        PINNED,
        `community-model ${f}/${key} (${entry.ref}) mist een gepinde versie-hash`,
      );
    }
  }
  // De Boost-default zelf: crystal-upscaler gepind én prefix intact voor
  // upscaleInputFor (lib/replicate.ts matcht op het slug-prefix).
  assert.match(defaultModelRef("upscale"), /^philz1337x\/crystal-upscaler:[a-f0-9]{64}$/);
}
console.log("models.ts smoke OK");
