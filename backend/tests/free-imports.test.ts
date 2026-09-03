// E14.11 — /v1/account must report the EFFECTIVE free-import counter,
// max(account, device), the same rule /v1/import-claim denies on. Pure
// mapping (lib/freeImports.ts) so no Supabase/env is needed.
import assert from "node:assert/strict";
import test from "node:test";

import { freeImportCounters } from "../lib/freeImports.js";

const ALLOWANCE = 3;

test("signed-out device on the cap → 0 remaining (was: hardcoded 3)", () => {
  assert.deepEqual(freeImportCounters(0, 3, ALLOWANCE), {
    free_imports_used: 3,
    free_imports_remaining: 0,
  });
});

test("signed-in free account: device counter wins when higher than the account counter", () => {
  assert.deepEqual(freeImportCounters(1, 3, ALLOWANCE), {
    free_imports_used: 3,
    free_imports_remaining: 0,
  });
});

test("account counter wins when the device is fresh", () => {
  assert.deepEqual(freeImportCounters(2, 0, ALLOWANCE), {
    free_imports_used: 2,
    free_imports_remaining: 1,
  });
});

test("nothing spent anywhere → full allowance", () => {
  assert.deepEqual(freeImportCounters(0, 0, ALLOWANCE), {
    free_imports_used: 0,
    free_imports_remaining: 3,
  });
});

test("missing fingerprint / null counters and over-cap values clamp into 0..allowance", () => {
  assert.deepEqual(freeImportCounters(null, undefined, ALLOWANCE), {
    free_imports_used: 0,
    free_imports_remaining: 3,
  });
  assert.deepEqual(freeImportCounters(7, -2, ALLOWANCE), {
    free_imports_used: 3,
    free_imports_remaining: 0,
  });
});
