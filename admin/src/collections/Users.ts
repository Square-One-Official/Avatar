import type { CollectionConfig } from "payload";
import { auditHooks } from "../lib/audit-hooks";
import { authed } from "../lib/access";

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
    admin: authed,
    create: authed,
    read: authed,
    update: authed,
    delete: authed,
  },
  fields: [],
  hooks: (() => {
    const a = auditHooks<{ email?: string }>(
      "users",
      (doc) => doc.email ?? "(unknown email)",
    );
    return {
      afterChange: [a.afterChange],
      afterDelete: [a.afterDelete],
    };
  })(),
};
