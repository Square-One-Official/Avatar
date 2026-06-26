import type { CollectionConfig } from "payload";
import { auditHooks } from "../lib/audit-hooks";

/**
 * CMS-driven Banner presets (E39). Each row is a starting point shown in the
 * macOS app's Banners empty-state / home. The app fetches this list at runtime
 * via `GET /v1/banner-presets`, so adding a row ships a new preset WITHOUT an
 * app or backend release. Picking one opens the Banner Studio prefilled.
 *
 * A preset = a stable `key`, a `label`, a `category` (grouping), an optional
 * `thumbnail` (wide preview), and a `config` — a JSON string of the app's
 * `BannerLayers` layer-stack (fill / texts / logo / shaders). The app decodes
 * `config` into BannerLayers; keep it valid JSON.
 *
 * Example config (solid fill):  {"fill":{"solid":{"hex":"#1C1917"}},"texts":[],"shaders":[]}
 */
export const BannerPresets: CollectionConfig = {
  slug: "banner-presets",
  admin: {
    useAsTitle: "label",
    defaultColumns: ["label", "key", "category", "order", "active"],
    description:
      "Starting points shown in the app's Banners empty-state. Add a row to ship a new preset without an app update — the app reads this list at runtime.",
  },
  access: {
    read: ({ req }) => Boolean(req.user) || Boolean(req.headers.get("authorization")),
    create: ({ req }) => Boolean(req.user),
    update: ({ req }) => Boolean(req.user),
    delete: ({ req }) => Boolean(req.user),
  },
  fields: [
    {
      name: "key",
      type: "text",
      required: true,
      unique: true,
      admin: {
        description:
          'Stable slug, e.g. "minimal-white". Lowercase, no spaces. NEVER change once live — it doubles as the cache key.',
      },
    },
    {
      name: "label",
      type: "text",
      required: true,
      admin: { description: 'Display name on the preset card, e.g. "Minimal White".' },
    },
    {
      name: "category",
      type: "select",
      required: false,
      defaultValue: "default",
      options: [
        { label: "Default", value: "default" },
        { label: "Minimal", value: "minimal" },
        { label: "Bold", value: "bold" },
        { label: "Playful", value: "playful" },
        { label: "Gradient", value: "gradient" },
      ],
      admin: { description: "Groups presets into sections in the app." },
    },
    {
      name: "thumbnail",
      type: "upload",
      relationTo: "media",
      required: false,
      admin: {
        description:
          "Wide preview shown on the card (≈1500×500, 3:1). If empty, the app renders the layer-stack itself.",
      },
    },
    {
      name: "config",
      type: "textarea",
      required: true,
      admin: {
        description:
          'JSON-serialized BannerLayers layer-stack. Example: {"fill":{"meshGradient":{"stops":[{"hex":"#6EC6FF","x":0,"y":0},{"hex":"#E3F2FF","x":1,"y":1}]}},"texts":[],"shaders":[]}',
      },
    },
    {
      name: "order",
      type: "number",
      required: false,
      defaultValue: 99,
      admin: { description: "Lower numbers appear first." },
    },
    {
      name: "active",
      type: "checkbox",
      required: false,
      defaultValue: true,
      admin: {
        description: "Uncheck to hide the preset from the app without deleting it.",
        position: "sidebar",
      },
    },
  ],
  hooks: (() => {
    const a = auditHooks<{ label?: string; key?: string }>(
      "banner-presets",
      (doc) => doc.label ?? doc.key ?? "(unnamed)",
    );
    return {
      afterChange: [a.afterChange],
      afterDelete: [a.afterDelete],
    };
  })(),
};
