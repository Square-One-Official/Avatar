/**
 * E55 — vaste ratio-sets van modellen zonder `match_input_image`.
 *
 * Pure data, bewust los van lib/image.ts (sharp) én lib/models.ts: de
 * registry (models.ts) wordt ook door lambdas zonder beeldwerk geïmporteerd
 * (cutout), en de ratio-keuze (nearestFixedAspect, image.ts) hoort niet aan
 * de registry vast. Beide importeren dit datamoduul.
 *
 * Schema-bron (2026-08-02): replicate.com/openai/gpt-image-1.5 resp.
 * /openai/gpt-image-2 — 2.0 kent óók expliciete pixelmaten en "auto"; die
 * slaan we bewust over (auto = "model kiest", niet "volg de input") en
 * padden altijd naar een expliciete dichtstbijzijnde ratio.
 */

export type FixedAspectKey =
  | "1:1"
  | "3:2"
  | "2:3"
  | "4:3"
  | "3:4"
  | "16:9"
  | "9:16";

export interface FixedAspect {
  key: FixedAspectKey;
  ratio: number;
}

/** gpt-image-1.5: alleen de drie klassieke ratio's. */
export const GPT_IMAGE_ASPECTS: FixedAspect[] = [
  { key: "1:1", ratio: 1 },
  { key: "3:2", ratio: 1.5 },
  { key: "2:3", ratio: 2 / 3 },
];

/**
 * gpt-image-2: de uitgebreide set. Met 3:4/9:16 erbij ligt er voor vrijwel
 * elk portret een ratio dicht bij de input → het E55.1-pad/crop-contract
 * padt dun tot niets, wat letterbox-artefacten verder terugdringt.
 */
export const GPT_IMAGE_2_ASPECTS: FixedAspect[] = [
  { key: "1:1", ratio: 1 },
  { key: "3:2", ratio: 1.5 },
  { key: "2:3", ratio: 2 / 3 },
  { key: "4:3", ratio: 4 / 3 },
  { key: "3:4", ratio: 3 / 4 },
  { key: "16:9", ratio: 16 / 9 },
  { key: "9:16", ratio: 9 / 16 },
];
