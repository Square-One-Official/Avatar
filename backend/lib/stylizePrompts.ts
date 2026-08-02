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
