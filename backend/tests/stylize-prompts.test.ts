import assert from "node:assert/strict";
import test from "node:test";
import {
  BALLOON_COMPOSITION_CLAUSE,
  DIE_CUT_COMPOSITION_CLAUSE,
  FRAMING_CLAUSE,
  STYLE_REFERENCE_CLAUSE,
  composeEffectPrompt,
  compositionClause,
  isDieCutStyle,
} from "../lib/stylizePrompts.js";

// Sticker-fix (2026-09-02): een die-cut-stijl mag NIET de framing-clausule
// krijgen (die maakt van de cutout-onderrand een rechte sticker-rand) en
// krijgt de compositie-clausule (gesloten omtrek, gecentreerd met marge).

test("sticker and balloon are free-standing styles, the others are not", () => {
  assert.equal(isDieCutStyle("sticker"), true);
  assert.equal(isDieCutStyle("balloon"), true);
  for (const key of ["windy", "flowers", "3d-head", "hairy", "clay"]) {
    assert.equal(isDieCutStyle(key), false, key);
    assert.equal(compositionClause(key), null, key);
  }
});

test("balloon prompt drops the framing clause and adds the balloon composition clause", () => {
  const prompt = composeEffectPrompt({
    basePrompt: "BASE.",
    styleKey: "balloon",
    hasStyleReferences: true,
    preserveFraming: true,
  });
  assert.equal(prompt, `BASE. ${STYLE_REFERENCE_CLAUSE} ${BALLOON_COMPOSITION_CLAUSE}`);
  assert.equal(prompt.includes(FRAMING_CLAUSE), false);
  assert.equal(prompt.includes(DIE_CUT_COMPOSITION_CLAUSE), false);
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
