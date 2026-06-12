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
assert.ok(
  (Object.keys(MODEL_REGISTRY) as Array<keyof typeof MODEL_REGISTRY>).every((f) => {
    const r = MODEL_REGISTRY[f];
    return r.requiresCloud && r.credits >= 1 && !!r.models[r.defaultModel];
  }),
);
console.log("models.ts smoke OK");
