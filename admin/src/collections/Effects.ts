import type { CollectionConfig } from "payload";
import { auditHooks } from "../lib/audit-hooks";
import { authed } from "../lib/access";

/**
 * CMS-driven Effects styles (E33). Each row is one card in the macOS Editor's
 * Effects panel. The app fetches this list at runtime via `GET /v1/effects`,
 * so adding a row ships a new effect WITHOUT an app or backend release.
 *
 * Three things make an effect: a stable `key` (sent to the image model and
 * used as the on-device cache key), a `thumbnail` (the card preview), and a
 * `prompt` (the full instruction the model runs). The prompt never leaves the
 * server — `/v1/effects` omits it; only `/v1/stylize` reads it. Optional
 * `styleReferences` (E54) are example images sent to the model alongside the
 * prompt; like the prompt they stay server-side.
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
    // Authenticated principals only. The backend reads with a valid Payload
    // API key (`Authorization: users API-Key <key>`), which Payload resolves
    // to `req.user` after validating the key — so `Boolean(req.user)` covers
    // the macOS-app read path. Do NOT also allow on mere header presence: an
    // unvalidated `Authorization: ...` header would have leaked the
    // server-only `prompt` field to any anonymous caller.
    read: authed,
    create: authed,
    update: authed,
    delete: authed,
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
      name: "styleReferences",
      type: "array",
      required: false,
      maxRows: 4,
      admin: {
        description:
          "Example images of the target style (E54). They are sent to the image model together with the prompt, so the result matches these examples much more closely than a text prompt alone.\n\n" +
          "What makes a good reference: a finished output in exactly the style you want (material, brushwork, palette, lighting). Prefer images WITHOUT a prominent recognizable face — the model can borrow facial features from reference people (identity bleed). If a face is unavoidable, keep it small or turned away.\n\n" +
          "1–3 images is the sweet spot; the backend sends at most 3. Like the prompt, references never leave the server.",
      },
      fields: [
        {
          name: "image",
          type: "upload",
          relationTo: "media",
          required: true,
        },
      ],
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
