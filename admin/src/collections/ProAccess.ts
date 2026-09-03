import type { CollectionConfig } from "payload";
import { auditHooks } from "../lib/audit-hooks";
import { adminSession, authed } from "../lib/access";

/**
 * E14.9 — the Pro list, manageable from the CMS.
 *
 * Before this collection the only way to hand someone Pro without a Stripe
 * subscription was the `DEV_UNLIMITED_EMAILS` environment variable on the
 * avatars-api Vercel project: editing it meant a redeploy, left no record of
 * who was added or why, and had exactly one setting (unlimited everything).
 * This collection replaces it as the primary source; the env var stays live
 * as a break-glass fallback for when the CMS is unreachable.
 *
 * Two levels, because "give this person Pro" and "this is my dev account"
 * are different needs:
 *
 *   - `pro` (default) — a comped subscription. Every Pro gate opens and the
 *     account gets `monthlyCredits` credits per calendar month, topped up
 *     (not stacked) on first use of each month. Cloud actions cost credits
 *     exactly as they do for a paying subscriber, so a comped account can't
 *     quietly run up an unbounded Replicate bill.
 *   - `unlimited` — the internal/dev level the env var used to grant: every
 *     credit check bypassed, plus the Advanced model-picker in the app
 *     (`is_dev_unlimited` on /v1/account, E15.5). Only for our own accounts.
 *
 * Read access is `authed` so the backend's API-key user can fetch the list.
 * Writes are `adminSession` — the backend key must never be able to grant
 * entitlements, only read them.
 */
export const ProAccess: CollectionConfig = {
  slug: "pro-access",
  labels: {
    singular: "Pro access",
    plural: "Pro access",
  },
  admin: {
    useAsTitle: "email",
    defaultColumns: ["email", "access", "active", "expiresAt", "note"],
    description:
      "Accounts that get Pro without paying. Matched on the email the user signs in with — an entry for an address that never signs up simply does nothing.",
    group: "Access",
  },
  access: {
    read: authed,
    create: adminSession,
    update: adminSession,
    delete: adminSession,
  },
  fields: [
    {
      name: "email",
      type: "email",
      required: true,
      unique: true,
      index: true,
      admin: {
        description:
          "Must match the address the user signs in with (Supabase auth email). Lowercased on save.",
      },
      hooks: {
        beforeChange: [
          ({ value }) => (typeof value === "string" ? value.trim().toLowerCase() : value),
        ],
      },
    },
    {
      name: "access",
      type: "select",
      required: true,
      defaultValue: "pro",
      options: [
        { label: "Pro (comped subscription, monthly credits)", value: "pro" },
        { label: "Unlimited (internal / dev — no credit limits)", value: "unlimited" },
      ],
      admin: {
        description:
          "Pro = everything a paying subscriber gets. Unlimited = no credit accounting at all + the Advanced model picker; keep this for our own accounts.",
      },
    },
    {
      name: "monthlyCredits",
      type: "number",
      required: true,
      defaultValue: 200,
      min: 0,
      max: 10_000,
      admin: {
        description:
          "Credits granted per calendar month. Tops the balance up to this number on first use of the month — unspent credits do not stack.",
        condition: (_, siblingData) => siblingData?.access !== "unlimited",
      },
    },
    {
      name: "active",
      type: "checkbox",
      defaultValue: true,
      index: true,
      admin: {
        description:
          "Uncheck to revoke without losing the record of who had access. Takes effect within a minute (backend caches the list for 60s).",
      },
    },
    {
      name: "expiresAt",
      type: "date",
      admin: {
        description:
          "Optional. After this moment the entry stops granting anything, no edit needed. Leave empty for open-ended access.",
        date: { pickerAppearance: "dayAndTime" },
      },
    },
    {
      name: "note",
      type: "text",
      admin: {
        description:
          "Who this is and why they're on the list (press, beta tester, refund make-good, …). Shows up in the audit log.",
      },
    },
    {
      name: "grantedAt",
      type: "date",
      defaultValue: () => new Date().toISOString(),
      admin: { readOnly: true, position: "sidebar" },
    },
  ],
  hooks: (() => {
    const a = auditHooks<{ email?: string; access?: string; active?: boolean }>(
      "pro-access",
      (doc) =>
        `${doc.email ?? "(no email)"} — ${doc.access ?? "pro"}${doc.active === false ? " (inactive)" : ""}`,
    );
    return {
      afterChange: [a.afterChange],
      afterDelete: [a.afterDelete],
    };
  })(),
};
