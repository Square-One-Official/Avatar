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
    // Payload's built-in /admin/create-first-user route bypasses
    // access.create when the users table is empty, so we can keep
    // this strict. Once a user exists, only signed-in users can
    // create more admins.
    admin: ({ req }) => Boolean(req.user),
    create: ({ req }) => Boolean(req.user),
    read: ({ req }) => Boolean(req.user),
    update: ({ req }) => Boolean(req.user),
    delete: ({ req }) => Boolean(req.user),
  },
  fields: [],
};
