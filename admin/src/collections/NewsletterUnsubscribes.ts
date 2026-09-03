import type { CollectionConfig } from "payload";
import { auditHooks } from "../lib/audit-hooks";
import { authed } from "../lib/access";

/**
 * Record of email addresses that have opted out of the announcement
 * newsletter (audit HIGH #15). Written by the backend's
 * `/v1/unsubscribe` endpoint via the Payload API key when a user clicks
 * the unsubscribe link in an email; read by `sendNewsletter` to filter
 * recipients before each blast.
 *
 * Access policy:
 *   - read / update / delete: authenticated admins only.
 *   - create: any authenticated principal (the backend's API-key user
 *     satisfies `req.user` after Payload validates the key, so this
 *     allows backend POSTs without granting public writes).
 *
 * The `email` field is indexed + unique so backend retries on the same
 * address are idempotent at the DB level — the backend just swallows the
 * uniqueness conflict instead of having to read-then-write.
 */
export const NewsletterUnsubscribes: CollectionConfig = {
  slug: "newsletter-unsubscribes",
  admin: {
    useAsTitle: "email",
    defaultColumns: ["email", "source", "unsubscribedAt"],
    description:
      "Users who clicked the unsubscribe link in a newsletter email. Filtered out of every audience before send.",
  },
  access: {
    read: authed,
    create: authed,
    update: authed,
    delete: authed,
  },
  fields: [
    {
      name: "email",
      type: "email",
      required: true,
      unique: true,
      index: true,
      admin: {
        description: "Lowercased before storage; case-insensitive uniqueness.",
      },
      hooks: {
        beforeChange: [
          ({ value }) => (typeof value === "string" ? value.trim().toLowerCase() : value),
        ],
      },
    },
    {
      name: "unsubscribedAt",
      type: "date",
      required: true,
      defaultValue: () => new Date().toISOString(),
      admin: { readOnly: true },
    },
    {
      name: "source",
      type: "select",
      defaultValue: "one_click",
      options: [
        { label: "One-click email link", value: "one_click" },
        { label: "RFC 8058 List-Unsubscribe-Post", value: "list_unsubscribe_post" },
        { label: "Manual (admin)", value: "manual" },
      ],
    },
  ],
  hooks: (() => {
    const a = auditHooks<{ email?: string; source?: string }>(
      "newsletter-unsubscribes",
      (doc) => doc.email ?? "(no email)",
    );
    return {
      afterChange: [a.afterChange],
      afterDelete: [a.afterDelete],
    };
  })(),
};
