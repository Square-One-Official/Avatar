import type { CollectionConfig } from "payload";
import { auditHooks } from "../lib/audit-hooks";

/**
 * CMS-driven Effects styles (E33). Each row is one card in the macOS Editor's
 * Effects panel. The app fetches this list at runtime via `GET /v1/effects`,
 * so adding a row ships a new effect WITHOUT an app or backend release.
 *
 * Three things make an effect: a stable `key` (sent to the image model and
 * used as the on-device cache key), a `thumbnail` (the card preview), and a
 * `prompt` (the full instruction the model runs). The prompt never leaves the
 * server — `/v1/effects` omits it; only `/v1/stylize` reads it.
 *
 * Seed the four launch effects on first deploy (copy the prompts from
 * `backend/api/v1/stylize.ts` → STYLE_PROMPTS):
 *   - clay / Clay · wood / Wood · 3d / 3D · scribble / Scribble
 */
export const Effects: CollectionConfig = {
  slug: "effects",
  admin: {
    useAsTitle: "label",
    defaultColumns: ["label", "key", "order", "active"],
    description:
      "Styles shown in the macOS Editor's Effects panel. Add a row to ship a new effect without an app update — the app reads this list at runtime.",
  },
  access: {
    // Authed admin OR any request carrying an Authorization header — the
    // backend reads with `Authorization: users API-Key <key>`. Mirrors
    // BadgeComponents so the macOS-app read path works.
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
          'Stable slug sent to the image model, e.g. "clay" or "oil-painting". Lowercase, no spaces. NEVER change it once the effect is live — it doubles as the cache key on the device, so renaming it orphans every cached result.',
      },
    },
    {
      name: "label",
      type: "text",
      required: true,
      admin: { description: 'Display name on the card, e.g. "Clay".' },
    },
    {
      name: "thumbnail",
      type: "upload",
      relationTo: "media",
      required: false,
      admin: {
        description:
          "Square preview shown on the card (≈400×400 px). If empty, the card falls back to a sparkles icon.",
      },
    },
    {
      name: "styleReference",
      type: "upload",
      relationTo: "media",
      required: false,
      admin: {
        description:
          "Optional example output sent to the AI model as a visual style guide alongside the prompt. Use a full-face portrait with this effect already applied — the model will match its style. Leave empty to rely on the prompt alone.",
        position: "sidebar",
      },
    },
    {
      name: "prompt",
      type: "textarea",
      required: true,
      admin: {
        description:
          "Full instruction sent to the image model.\n\n" +
          "Good format:\n" +
          '"Transform this portrait into a claymation-style clay sculpture: smooth modelling-clay skin, hand-sculpted texture, soft studio lighting. Keep the person\'s facial features, expression, hairstyle and clothing clearly recognizable so the person remains identifiable."\n\n' +
          "Tips: start with “Transform this portrait into…”, describe the material / texture / lighting, then ALWAYS end with the identity sentence above so the result still looks like the same person.",
      },
    },
    {
      name: "order",
      type: "number",
      required: false,
      defaultValue: 99,
      admin: { description: "Lower numbers appear first in the panel." },
    },
    {
      name: "active",
      type: "checkbox",
      required: false,
      defaultValue: true,
      admin: {
        description: "Uncheck to hide the effect from the app without deleting it.",
        position: "sidebar",
      },
    },
  ],
  hooks: (() => {
    const a = auditHooks<{ label?: string; key?: string }>(
      "effects",
      (doc) => doc.label ?? doc.key ?? "(unnamed)",
    );
    return {
      afterChange: [a.afterChange],
      afterDelete: [a.afterDelete],
    };
  })(),
};
