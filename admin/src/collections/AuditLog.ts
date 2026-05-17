import type { CollectionConfig } from "payload";

/**
 * Append-only record of every admin mutation (audit MEDIUM #24). Each row
 * captures who changed what, when, and a short summary tag — enough for
 * incident response without storing the full document diff. Writes are
 * exclusively performed by the `auditHooks` factory in
 * `src/lib/audit-hooks.ts`; the collection's access policy refuses every
 * other mutation path so a leaked admin session can't quietly tamper with
 * the trail.
 *
 * Why "exclusively via hooks": Payload's `req.payload.create()` inside a
 * hook bypasses the collection's `access.create` check (the hook is
 * already running with full server privileges), so we can keep
 * `access.create` set to deny-anything-public while letting the hook
 * write. That gives us an immutable-from-the-outside log without a
 * separate database role.
 */
export const AuditLog: CollectionConfig = {
  slug: "audit-log",
  admin: {
    useAsTitle: "summary",
    defaultColumns: ["at", "action", "collection", "summary", "actorEmail"],
    description:
      "Append-only audit trail of admin mutations. Captures the actor, " +
      "action, target collection, and a short summary. Read-only via the " +
      "admin UI; writes happen via collection hooks.",
    pagination: {
      defaultLimit: 50,
    },
    // Newest first by default — admins land in the log to see the most
    // recent activity, not the earliest.
    listSearchableFields: ["summary", "collection", "action", "actorEmail"],
  },
  access: {
    // Read: any authenticated admin can see the trail.
    read: ({ req }) => Boolean(req.user),
    // Write paths all refuse. Hooks bypass `access.create` because they
    // run server-side with `req.payload.create`, so this denial only
    // gates direct HTTP creates.
    create: () => false,
    update: () => false,
    delete: () => false,
  },
  fields: [
    {
      name: "at",
      type: "date",
      required: true,
      defaultValue: () => new Date().toISOString(),
      admin: { readOnly: true, date: { displayFormat: "yyyy-MM-dd HH:mm:ss" } },
    },
    {
      name: "action",
      type: "select",
      required: true,
      options: [
        { label: "Created", value: "created" },
        { label: "Updated", value: "updated" },
        { label: "Deleted", value: "deleted" },
      ],
      admin: { readOnly: true },
    },
    {
      name: "collection",
      type: "text",
      required: true,
      admin: {
        readOnly: true,
        description: "Slug of the affected collection.",
      },
    },
    {
      name: "docId",
      type: "text",
      required: true,
      admin: {
        readOnly: true,
        description: "ID of the affected document (kept as text — Payload IDs can be UUIDs, ObjectIds, or integers depending on adapter).",
      },
    },
    {
      name: "summary",
      type: "text",
      required: true,
      admin: {
        readOnly: true,
        description:
          "Short, low-cardinality tag (title / slug / email). Never stores secrets or full diffs.",
      },
    },
    {
      name: "actor",
      type: "relationship",
      relationTo: "users",
      admin: {
        readOnly: true,
        description: "Authenticated user who performed the action. Cleared if the user is later deleted (the row stays).",
      },
    },
    {
      name: "actorEmail",
      type: "text",
      admin: {
        readOnly: true,
        description:
          "Denormalised actor email — survives the user being deleted, which `actor` would not.",
      },
    },
  ],
};
