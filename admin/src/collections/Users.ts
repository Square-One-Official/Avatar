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
    // Bootstrap: allow create when the users table is empty so the
    // first-user flow at /admin/create-first-user can succeed. After
    // that, only signed-in users can create more admins. Payload's
    // built-in /admin/create-first-user route also enforces this from
    // the UI side.
    create: async ({ req }) => {
      if (req.user) return true;
      const { totalDocs } = await req.payload.count({ collection: "users" });
      return totalDocs === 0;
    },
    read: ({ req }) => Boolean(req.user),
    update: ({ req }) => Boolean(req.user),
    delete: ({ req }) => Boolean(req.user),
  },
  fields: [],
};
