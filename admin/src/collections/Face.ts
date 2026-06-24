import type { CollectionConfig } from "payload";
import { auditHooks } from "../lib/audit-hooks";

/**
 * CMS-gestuurde face-presets (E33+). Elke rij is één kaart in het Face-paneel.
 * De prompt wordt server-side opgehaald in `/v1/stylize` en nooit naar de client
 * gestuurd. Geen vrij promptveld (productie-whitelist). Toevoegen = nieuwe kaart
 * zonder app-release.
 *
 * Seed (3 bestaande presets): whiten-teeth / apply-makeup / reduce-wrinkles
 * — prompts overnemen uit FACE_PRESETS in backend/api/v1/stylize.ts.
 */
export const Face: CollectionConfig = {
  slug: "face-presets",
  admin: {
    useAsTitle: "label",
    defaultColumns: ["label", "key", "order", "active"],
    description: "Face beauty-presets in het Face-paneel. Voeg een rij toe om een nieuwe kaart te krijgen zonder app-update.",
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
          'Stabiele slug, bv. "whiten-teeth" of "smooth-skin". Lowercase + hyphens. Nooit wijzigen als de preset live is — het is de server-side opzoeksleutel.',
      },
    },
    {
      name: "label",
      type: "text",
      required: true,
      admin: { description: 'Weergavenaam op de kaart, bv. "Whiten teeth" of "Smooth skin".' },
    },
    {
      name: "prompt",
      type: "textarea",
      required: true,
      admin: {
        description:
          "Volledige instructie-prompt voor het AI-model. Sluit altijd af met de face-clausule: " +
          "\"Keep the person's identity, facial structure, expression, pose, hair, clothing and background exactly the same. " +
          "Change only the requested facial detail and nothing else, keeping the result photorealistic and natural.\"",
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
      "face-presets",
      (doc) => doc.label ?? doc.key ?? "(unnamed)",
    );
    return { afterChange: [a.afterChange], afterDelete: [a.afterDelete] };
  })(),
};
