import type { CollectionConfig } from "payload";

/**
 * Admin operators. Just one user (you) at first. API-key auth is enabled
 * so the backend at api.aaavatar.nl can authenticate against Payload's
 * REST API without a session cookie — see `lib/payload.ts` in the
 * backend.
 */
export const Users: CollectionConfig = {
  slug: "users",
  admin: {
    useAsTitle: "email",
  },
  auth: {
    useAPIKey: true,
    tokenExpiration: 60 * 60 * 8,
  },
  access: {
    // Lock the admin to authenticated users only — there is no
    // public-self-signup. Add a new admin by creating a user via the
    // Payload local API or directly in the DB.
    create: ({ req }) => Boolean(req.user),
    read: ({ req }) => Boolean(req.user),
    update: ({ req }) => Boolean(req.user),
    delete: ({ req }) => Boolean(req.user),
  },
  fields: [],
};
