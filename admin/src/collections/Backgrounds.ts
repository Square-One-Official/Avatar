import type { CollectionConfig } from "payload";
import { auditHooks } from "../lib/audit-hooks";

/**
 * CMS-driven background images (E33+). Each row is one swatch in the macOS
 * Editor's Background panel, grouped by `category`. Adding a row ships a new
 * background WITHOUT an app or backend release.
 *
 * Two images per row:
 *   - `image`     — full-res background used for compositing the final export
 *   - `thumbnail` — small square swatch shown in the panel (≈200×200 px).
 *                   Leave empty to fall back to the full image (slower to load).
 *
 * `category` is a free-text label (e.g. "Nature", "Abstract", "Studio").
 * The app groups rows by category and shows each group as a labelled section.
 */
export const Backgrounds: CollectionConfig = {
  slug: "backgrounds",
  admin: {
    useAsTitle: "label",
    defaultColumns: ["label", "category", "order", "active"],
    description:
      "Background images shown in the macOS Editor's Background panel, grouped by category. Add a row to ship a new background without an app update.",
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
          'Stable slug, e.g. "forest-mist" or "studio-grey". Lowercase, hyphens only. NEVER change once live — it is the on-device cache key.',
      },
    },
    {
      name: "label",
      type: "text",
      required: true,
      admin: { description: 'Display name shown on hover, e.g. "Forest Mist".' },
    },
    {
      name: "category",
      type: "text",
      required: true,
      admin: {
        description:
          'Group label shown as a section header, e.g. "Nature", "Abstract", "Studio", "Gradient". Rows with the same category string are grouped together.',
      },
    },
    {
      name: "image",
      type: "upload",
      relationTo: "media",
      required: true,
      admin: {
        description:
          "Full-resolution background image used when compositing the final export. Minimum 1000×1000 px recommended.",
      },
    },
    {
      name: "thumbnail",
      type: "upload",
      relationTo: "media",
      required: false,
      admin: {
        description:
          "Small square swatch (≈200×200 px) shown in the panel. Falls back to the full image if empty.",
        position: "sidebar",
      },
    },
    {
      name: "order",
      type: "number",
      required: false,
      defaultValue: 99,
      admin: {
        description: "Lower numbers appear first within the same category.",
        position: "sidebar",
      },
    },
    {
      name: "active",
      type: "checkbox",
      required: false,
      defaultValue: true,
      admin: {
        description: "Uncheck to hide this background without deleting it.",
        position: "sidebar",
      },
    },
  ],
  hooks: (() => {
    const a = auditHooks<{ label?: string; key?: string }>(
      "backgrounds",
      (doc) => doc.label ?? doc.key ?? "(unnamed)",
    );
    return {
      afterChange: [a.afterChange],
      afterDelete: [a.afterDelete],
    };
  })(),
};
