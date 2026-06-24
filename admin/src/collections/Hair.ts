import type { CollectionConfig } from "payload";
import { auditHooks } from "../lib/audit-hooks";

/**
 * CMS-gestuurde kapsel-presets (E33+). Elke rij is één chip in het Hair-paneel.
 * De prompt wordt server-side opgehaald in `/v1/stylize` en nooit naar de client
 * gestuurd. Toevoegen = nieuwe chip in de app zonder release.
 *
 * Seed (5 bestaande presets): trim-flyaways / curly / straight / short / updo
 * — prompts overnemen uit HAIR_PRESETS in backend/api/v1/stylize.ts.
 */
export const Hair: CollectionConfig = {
  slug: "hair-presets",
  admin: {
    useAsTitle: "label",
    defaultColumns: ["label", "key", "order", "active"],
    description: "Kapsel-presets in het Hair-paneel. Voeg een rij toe om een nieuwe chip te krijgen zonder app-update.",
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
          'Stabiele slug, bv. "curly" of "beach-waves". Lowercase + hyphens. Nooit wijzigen als de preset live is — het is de server-side opzoeksleutel.',
      },
    },
    {
      name: "label",
      type: "text",
      required: true,
      admin: { description: 'Weergavenaam op de chip, bv. "Curly" of "Beach waves".' },
    },
    {
      name: "prompt",
      type: "textarea",
      required: true,
      admin: {
        description:
          "Volledige instructie-prompt voor het AI-model. Begint met \"Change the hairstyle to…\". " +
          "Sluit altijd af met de haar-clausule: " +
          "\"Keep the face, expression and clothing exactly the same. Change nothing else about the image.\"",
      },
    },
    {
      name: "order",
      type: "number",
      required: false,
      defaultValue: 99,
      admin: { description: "Lagere nummers verschijnen eerder in de rij.", position: "sidebar" },
    },
    {
      name: "active",
      type: "checkbox",
      required: false,
      defaultValue: true,
      admin: { description: "Vink uit om de preset te verbergen zonder hem te verwijderen.", position: "sidebar" },
    },
  ],
  hooks: (() => {
    const a = auditHooks<{ label?: string; key?: string }>(
      "hair-presets",
      (doc) => doc.label ?? doc.key ?? "(unnamed)",
    );
    return { afterChange: [a.afterChange], afterDelete: [a.afterDelete] };
  })(),
};
