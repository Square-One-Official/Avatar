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
 * Vrijstaande stijlen (Sticker-fix, Thierry 2026-09-02; Balloon 2026-09-03):
 * het resultaat is één vrijstaande, rondom gesloten vorm — géén portret dat
 * tot de onderrand doorloopt. De FRAMING_CLAUSE is daar contraproductief: de
 * cutout raakt de onderrand (romp loopt uit beeld), het model neemt die rand
 * letterlijk over (sticker: rechte onderkant; balloon: romp + shirt blijven
 * staan en het shirt wordt de ballon). Voor deze keys vervalt de framing-
 * clausule en komt een per-stijl compositie-clausule ervoor in de plaats.
 * /v1/effects meldt dezelfde keys als `composition: "die_cut"` zodat de client
 * het resultaat als vrijstaande vorm kadert (content-fit, gecentreerd) i.p.v.
 * de oude portret-transform te hergebruiken.
 *
 * Bewust een server-constante, geen CMS-veld: één plek, geen admin-DDL, en
 * de bakeoff-driver deelt 'm 1-op-1.
 *
 * E55.13 (2026-09-04): de zichtbare rand komt sinds de client-fix van
 * `DieCutRenderer` (alpha-dilatie na de her-isolatie, hoofd-alleen-clip
 * onder de kin) — de model-rand is nog slechts een compositie-hint. Daarom
 * vraagt de clausule om een zuiver witte, harde rand: wat er van de model-
 * rand in de matte overblijft, valt dan wit-op-wit weg.
 */
export const DIE_CUT_COMPOSITION_CLAUSE =
  "Compose it as one complete die-cut sticker of the HEAD ONLY: the cut follows the outline of the hair and face and closes through the neck just below the chin with a smoothly rounded bottom edge, so the white border runs unbroken around the entire head, including underneath. The border must be solid pure white (#FFFFFF), flat and evenly thick, with a crisp hard edge: no shadow, glow, blur or texture on the border itself. Do not include the shoulders, shirt or torso, even though the clothing is mentioned above. The sticker must not touch or run off any edge of the image: place it in the centre with clear paper margin on every side, scaling it down if needed so the complete sticker, border included, fits inside the frame.";

/**
 * Balloon (2026-09-03): de bakeoff-runs hielden romp, shirt en handen en
 * bliezen het hoofd nauwelijks op — de framing-clausule verbood de vervorming
 * en de cutout-romp gaf het model iets om te bewaren. Deze clausule dwingt
 * hoofd-alleen, gesloten bij de knoop, gecentreerd met marge.
 */
export const BALLOON_COMPOSITION_CLAUSE =
  "Compose it as ONE complete free-floating balloon of the HEAD ONLY: the outline is a single closed balloon shape that ends in the tied rubber knot just below the chin, with only the thin string continuing downward. Do not include the neck, shoulders, shirt, hands or torso, and do not keep the original crop: place the whole balloon in the centre of the frame with clear empty margin on every side, scaling it down if needed so the entire balloon and its knot fit inside the image without touching any edge; the string may fade out toward the bottom edge.";

const COMPOSITION_CLAUSES: Readonly<Record<string, string>> = {
  sticker: DIE_CUT_COMPOSITION_CLAUSE,
  balloon: BALLOON_COMPOSITION_CLAUSE,
};

export const DIE_CUT_STYLE_KEYS: ReadonlySet<string> = new Set(Object.keys(COMPOSITION_CLAUSES));

export function isDieCutStyle(styleKey: string): boolean {
  return DIE_CUT_STYLE_KEYS.has(styleKey);
}

/** De compositie-clausule van een vrijstaande stijl; `null` voor portret-stijlen. */
export function compositionClause(styleKey: string): string | null {
  return COMPOSITION_CLAUSES[styleKey] ?? null;
}

/**
 * Effects-prompt exact zoals /v1/stylize 'm opbouwt (basis-prompt uit de CMS
 * + rolclausule bij refs + compositie-clausule bij vrijstaande stijlen + framing). Gedeeld met de
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
  const clause = compositionClause(input.styleKey);
  if (clause) prompt = `${prompt} ${clause}`;
  if (input.preserveFraming && !clause) prompt = `${prompt} ${FRAMING_CLAUSE}`;
  return prompt;
}
