import type { GlobalConfig } from "payload";

/**
 * App-brede visuele configuratie — singleton (Global) in Payload, zodat er
 * maar één document is en je het direct kunt bewerken zonder een rij te kiezen.
 *
 * Velden:
 *   splashBackground — de achtergrondafbeelding van het Onboarding Splash-scherm
 *                      (was een hardgecodeerde blauwe gradient-placeholder).
 *   emptyStateAvatars — maximaal 6 portret-voorbeelden in de cirkels op het
 *                       lege canvas (was `person.fill`-glyph-placeholders).
 *
 * Laat een veld leeg om de hardgecodeerde fallback in de app te tonen — zo
 * breekt de app nooit bij een ontbrekende configuratie.
 */
export const AppConfig: GlobalConfig = {
  slug: "app-config",
  label: "App configuration",
  access: {
    read: () => true,
    update: ({ req }) => Boolean(req.user),
  },
  fields: [
    {
      name: "splashBackground",
      type: "upload",
      relationTo: "media",
      required: false,
      admin: {
        description:
          "Full-bleed achtergrond van het eerste Onboarding-scherm (Splash). " +
          "Aanbevolen formaat: 1240×800 px of groter, 16:10-verhouding. " +
          "Leeg laten toont de ingebouwde blauwe gradient als fallback.",
      },
    },
    {
      name: "emptyStateAvatars",
      type: "array",
      label: "Empty state avatars (max 6)",
      maxRows: 6,
      required: false,
      admin: {
        description:
          "Maximaal 6 portret-voorbeelden die in de cirkels op het lege canvas " +
          "verschijnen zolang de gebruiker nog geen foto heeft geüpload. " +
          "Aanbevolen: vierkant portret ≥ 200×200 px. Volgorde is de positie in " +
          "de ring (linksboven → linksmidden → linksonder → etc.). " +
          "Leeg laten toont gekleurde placeholder-cirkels als fallback.",
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
  ],
};
