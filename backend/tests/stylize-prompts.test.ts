import assert from "node:assert/strict";
import test from "node:test";
import {
  DIE_CUT_COMPOSITION_CLAUSE,
  FRAMING_CLAUSE,
  STYLE_REFERENCE_CLAUSE,
  composeEffectPrompt,
  isDieCutStyle,
} from "../lib/stylizePrompts.js";

// Sticker-fix (2026-09-02): een die-cut-stijl mag NIET de framing-clausule
// krijgen (die maakt van de cutout-onderrand een rechte sticker-rand) en
// krijgt de compositie-clausule (gesloten omtrek, gecentreerd met marge).

test("sticker is a die-cut style, the others are not", () => {
  assert.equal(isDieCutStyle("sticker"), true);
  for (const key of ["balloon", "windy", "flowers", "3d-head", "hairy", "clay"]) {
    assert.equal(isDieCutStyle(key), false, key);
  }
});

test("die-cut prompt drops the framing clause and adds the composition clause", () => {
  const prompt = composeEffectPrompt({
    basePrompt: "BASE.",
    styleKey: "sticker",
    hasStyleReferences: true,
    preserveFraming: true,
  });
  assert.equal(prompt, `BASE. ${STYLE_REFERENCE_CLAUSE} ${DIE_CUT_COMPOSITION_CLAUSE}`);
  assert.equal(prompt.includes(FRAMING_CLAUSE), false);
});

test("portrait styles keep the framing clause and get no composition clause", () => {
  const prompt = composeEffectPrompt({
    basePrompt: "BASE.",
    styleKey: "windy",
    hasStyleReferences: false,
    preserveFraming: true,
  });
  assert.equal(prompt, `BASE. ${FRAMING_CLAUSE}`);
  assert.equal(prompt.includes(DIE_CUT_COMPOSITION_CLAUSE), false);
});

test("without preserve_framing no framing clause is added", () => {
  const prompt = composeEffectPrompt({
    basePrompt: "BASE.",
    styleKey: "windy",
    hasStyleReferences: true,
    preserveFraming: false,
  });
  assert.equal(prompt, `BASE. ${STYLE_REFERENCE_CLAUSE}`);
});
