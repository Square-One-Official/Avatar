import type { GlobalConfig } from "payload";

/**
 * Remote feature flags (E33+) — singleton Global in Payload. Schakel
 * functies in of uit zonder een app- of backend-release. De iOS-app haalt
 * deze flags op bij startup; als de CMS onbereikbaar is, vallen alle flags
 * terug op `true` zodat de app nooit kapot gaat.
 *
 * Endpoint: GET /v1/feature-flags
 */
export const FeatureFlags: GlobalConfig = {
  slug: "feature-flags",
  label: "Feature flags",
  admin: {
    description:
      "Schakel app-functies in of uit zonder een release. " +
      "Als de CMS onbereikbaar is, zijn alle functies aan (veilige standaard).",
  },
  access: {
    read: () => true,
    update: ({ req }) => Boolean(req.user),
  },
  fields: [
    {
      name: "effectsEnabled",
      type: "checkbox",
      defaultValue: true,
      label: "Effects (AI stijl-effecten)",
      admin: { description: "Effects-paneel zichtbaar in de toolbar." },
    },
    {
      name: "hairEnabled",
      type: "checkbox",
      defaultValue: true,
      label: "Hair (kapselwissel)",
      admin: { description: "Hair-paneel zichtbaar in de toolbar." },
    },
    {
      name: "clothesEnabled",
      type: "checkbox",
      defaultValue: true,
      label: "Clothes (kledingwissel)",
      admin: { description: "Clothes-paneel zichtbaar in de toolbar." },
    },
    {
      name: "faceEnabled",
      type: "checkbox",
      defaultValue: true,
      label: "Face (beauty-edits)",
      admin: { description: "Face-paneel zichtbaar in de toolbar." },
    },
    {
      name: "backgroundsEnabled",
      type: "checkbox",
      defaultValue: true,
      label: "Background (achtergronden)",
      admin: { description: "Background-paneel zichtbaar in de toolbar." },
    },
  ],
};
