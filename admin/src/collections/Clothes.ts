import type { CollectionConfig } from "payload";
import { auditHooks } from "../lib/audit-hooks";

/**
 * CMS-gestuurde kleding-presets (E33+). Elke rij is één chip in het Clothes-paneel.
 * De prompt wordt server-side opgehaald in `/v1/stylize` en nooit naar de client
 * gestuurd. Toevoegen = nieuwe chip zonder app-release.
 *
 * Seed (5 bestaande presets): tshirt / polo / blazer / hoody / sweater
 * — prompts overnemen uit CLOTHES_PRESETS in backend/api/v1/stylize.ts.
 */
export const Clothes: CollectionConfig = {
  slug: "clothes-presets",
  admin: {
    useAsTitle: "label",
    defaultColumns: ["label", "key", "order", "active"],
    description: "Kleding-presets in het Clothes-paneel. Voeg een rij toe om een nieuwe chip te krijgen zonder app-update.",
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
          'Stabiele slug, bv. "blazer" of "turtleneck". Lowercase + hyphens. Nooit wijzigen als de preset live is — het is de server-side opzoeksleutel.',
      },
    },
    {
      name: "label",
      type: "text",
      required: true,
      admin: { description: 'Weergavenaam op de chip, bv. "Blazer" of "Turtleneck".' },
    },
    {
      name: "prompt",
      type: "textarea",
      required: true,
      admin: {
        description:
          "Volledige instructie-prompt voor het AI-model. Begint met \"Change the upper clothing to…\". " +
          "Sluit altijd af met de kleding-clausule: " +
          "\"Keep the face, hair, pose and background exactly the same. Change only the clothing, nothing else.\"",
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
      "clothes-presets",
      (doc) => doc.label ?? doc.key ?? "(unnamed)",
    );
    return { afterChange: [a.afterChange], afterDelete: [a.afterDelete] };
  })(),
};
