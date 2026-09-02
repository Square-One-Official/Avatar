/**
 * E55.7 — gedeelde prompt-clausules van /v1/stylize, in een side-effect-vrij
 * lib-moduul zodat de bakeoff-driver (scripts/effects-bakeoff.ts) exact de
 * productie-prompt kan nabouwen zónder de handler-module (en daarmee de
 * Supabase/auth-imports) binnen te trekken. /v1/stylize importeert ze hier —
 * één bron, geen drift.
 */

/** Client-flag `preserve_framing`: stylize op volle origineel → geen reframe. */
export const FRAMING_CLAUSE =
  "Keep the exact same crop, zoom, and position of the person in the frame — do not reframe, recenter, or change the composition.";

/**
 * E54: rolverdeling wanneer een effect CMS-stijlreferenties meestuurt. Zonder
 * deze clausule moet het model zelf raden welke input de persoon is en welke
 * de stijl — met identity-bleed uit de referenties als bekend gevolg.
 */
export const STYLE_REFERENCE_CLAUSE =
  "The first image is the person to transform. Every other image is a style example only: match its artistic style, colour palette, texture, brushwork and lighting exactly, but do not copy any person, face, pose or composition from the style examples.";

/**
 * Die-cut-stijlen (Sticker-fix, Thierry 2026-09-02): het resultaat is één
 * vrijstaande, rondom gesloten vorm — géén portret dat tot de onderrand
 * doorloopt. De FRAMING_CLAUSE is daar contraproductief: de cutout raakt de
 * onderrand (romp loopt uit beeld), het model neemt die rand letterlijk over
 * als rechte sticker-onderkant en de witte rand stopt daar. Voor deze keys
 * vervalt de framing-clausule en komt DIE_CUT_COMPOSITION_CLAUSE ervoor in
 * de plaats. /v1/effects meldt dezelfde keys als `composition: "die_cut"`
 * zodat de client het resultaat als vrijstaande vorm kadert (content-fit,
 * gecentreerd) i.p.v. de oude portret-transform te hergebruiken.
 *
 * Bewust een server-constante, geen CMS-veld: één plek, geen admin-DDL, en
 * de bakeoff-driver deelt 'm 1-op-1.
 */
export const DIE_CUT_STYLE_KEYS: ReadonlySet<string> = new Set(["sticker"]);

export function isDieCutStyle(styleKey: string): boolean {
  return DIE_CUT_STYLE_KEYS.has(styleKey);
}

export const DIE_CUT_COMPOSITION_CLAUSE =
  "Compose it as one complete die-cut sticker of the HEAD ONLY: the cut follows the outline of the hair and face and closes through the neck just below the chin with a smoothly rounded bottom edge, so the white border runs unbroken around the entire head, including underneath. Do not include the shoulders, shirt or torso. The sticker must not touch or run off any edge of the image: place it in the centre with clear paper margin on every side, scaling it down if needed so the complete sticker, border included, fits inside the frame.";

/**
 * Effects-prompt exact zoals /v1/stylize 'm opbouwt (basis-prompt uit de CMS
 * + rolclausule bij refs + die-cut-compositie + framing). Gedeeld met de
 * bakeoff-driver zodat een prompt-tweak hier meteen meetbaar is.
 */
export function composeEffectPrompt(input: {
  basePrompt: string;
  styleKey: string;
  hasStyleReferences: boolean;
  preserveFraming: boolean;
}): string {
  let prompt = input.basePrompt;
  if (input.hasStyleReferences) prompt = `${prompt} ${STYLE_REFERENCE_CLAUSE}`;
  const dieCut = isDieCutStyle(input.styleKey);
  if (dieCut) prompt = `${prompt} ${DIE_CUT_COMPOSITION_CLAUSE}`;
  if (input.preserveFraming && !dieCut) prompt = `${prompt} ${FRAMING_CLAUSE}`;
  return prompt;
}
