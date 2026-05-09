import type { CollectionConfig } from "payload";

/**
 * Registry of components in the macOS app that can wear a "NEW" badge.
 * Adding a row here makes the ID available in the Announcements →
 * badgeTargets dropdown. The string IDs must match the constants in
 * `Avatar/Services/AnnouncementService.swift` (`BadgeComponent`) — the
 * macOS app uses the ID as the lookup key into its in-memory badge map.
 *
 * Seed via the admin UI on first launch:
 *   - magic-cutout      → Magic Cutout button
 *   - fill-body         → Fill in Body button
 *   - colorize          → Colorise button
 *   - export-sheet      → Export sheet entry
 *   - backgrounds       → Backgrounds picker
 */
export const BadgeComponents: CollectionConfig = {
  slug: "badge-components",
  admin: {
    useAsTitle: "label",
    description: "IDs the macOS app knows about. Don't add IDs that aren't wired in code — the badge will silently no-op.",
  },
  access: {
    read: ({ req }) => Boolean(req.user) || Boolean(req.headers.get("authorization")),
    create: ({ req }) => Boolean(req.user),
    update: ({ req }) => Boolean(req.user),
    delete: ({ req }) => Boolean(req.user),
  },
  fields: [
    { name: "componentId", type: "text", required: true, unique: true },
    { name: "label", type: "text", required: true, admin: { description: "Human-readable name shown in the dropdown." } },
  ],
};
