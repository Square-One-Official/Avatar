import type { CollectionConfig } from "payload";

/**
 * The core CMS document. One Announcement drives:
 *   - the post-sign-in modal in the macOS app
 *   - any number of "NEW" badges on registered components
 *   - (optionally) an email newsletter blast via Resend
 *
 * Lifecycle: drafts have `publishedAt = null`. Set `publishedAt` to
 * make it live. The macOS-app feed only returns published, non-expired
 * docs. Field naming and shape are mirrored verbatim by
 * `lib/payload.ts` in the backend; renaming a field here means
 * updating the normalizer there.
 */
export const Announcements: CollectionConfig = {
  slug: "announcements",
  admin: {
    useAsTitle: "title",
    defaultColumns: ["title", "slug", "publishedAt", "audience", "frequency"],
  },
  access: {
    read: ({ req }) => Boolean(req.user) || Boolean(req.headers.get("authorization")),
    create: ({ req }) => Boolean(req.user),
    update: ({ req }) => Boolean(req.user),
    delete: ({ req }) => Boolean(req.user),
  },
  fields: [
    {
      name: "title",
      type: "text",
      required: true,
      admin: { description: "Modal headline. Keep it scannable — under ~40 chars." },
    },
    {
      name: "slug",
      type: "text",
      required: true,
      unique: true,
      admin: {
        description:
          "Stable identifier used to track 'seen' state per user. Once published, do NOT change — pick a new slug to re-show a campaign.",
      },
    },
    {
      name: "body",
      type: "richText",
      admin: { description: "Modal body. Inline styling and links only — block layouts are flattened." },
    },
    {
      name: "image",
      type: "upload",
      relationTo: "media",
      admin: { description: "16:9 hero image at the top of the modal and email." },
    },
    {
      name: "primaryCta",
      type: "group",
      admin: { description: "Optional CTA button. Leave both fields empty to render only the dismiss action." },
      fields: [
        { name: "label", type: "text" },
        { name: "url", type: "text" },
      ],
    },
    {
      name: "frequency",
      type: "select",
      required: true,
      defaultValue: "once",
      options: [
        { label: "Show once, ever", value: "once" },
        { label: "Show every sign-in until dismissed", value: "everySignInUntilDismissed" },
        { label: "Show until target date", value: "untilDate" },
        { label: "Show on Nth sign-in (delay)", value: "delayedNthSignIn" },
      ],
    },
    {
      name: "untilDate",
      type: "date",
      admin: {
        condition: (data) => data?.frequency === "untilDate",
        description: "Auto-expires on this date regardless of dismissal.",
      },
    },
    {
      name: "delayN",
      type: "number",
      admin: {
        condition: (data) => data?.frequency === "delayedNthSignIn",
        description: "Skip the first N sign-ins after publish. Useful for sticky-session users you don't want to interrupt right after release.",
      },
    },
    {
      name: "audience",
      type: "select",
      required: true,
      defaultValue: "all",
      options: [
        { label: "All users", value: "all" },
        { label: "Free users", value: "freeUsers" },
        { label: "Pro users", value: "proUsers" },
        { label: "Specific emails", value: "specificEmails" },
      ],
    },
    {
      name: "audienceEmails",
      type: "array",
      admin: {
        condition: (data) => data?.audience === "specificEmails",
        description: "Lower-cased and trimmed before comparison.",
      },
      fields: [{ name: "email", type: "email", required: true }],
    },
    {
      name: "minAppVersion",
      type: "text",
      admin: {
        description:
          "Semver gate, e.g. '1.2.0'. Clients on older versions won't see this announcement (they'll see whichever earlier one still applies).",
      },
    },
    {
      name: "publishedAt",
      type: "date",
      admin: {
        description:
          "Leave empty to keep as draft. Set to a past date to publish immediately, or future to schedule.",
        position: "sidebar",
      },
    },
    {
      name: "expiresAt",
      type: "date",
      admin: {
        description: "Hide from the feed after this moment, regardless of dismiss state.",
        position: "sidebar",
      },
    },
    {
      name: "badgeTargets",
      type: "array",
      admin: {
        description:
          "Each row paints a NEW pill on the corresponding registered component for the chosen number of days after publish. Empty = no badge.",
      },
      fields: [
        {
          name: "componentId",
          type: "relationship",
          relationTo: "badge-components",
          required: true,
        },
        {
          name: "durationDays",
          type: "number",
          required: true,
          defaultValue: 14,
          min: 1,
          max: 365,
        },
      ],
    },
    {
      name: "newsletter",
      type: "group",
      admin: { description: "Optional email distribution. Use the 'Send' panel below after publishing." },
      fields: [
        {
          name: "send",
          type: "checkbox",
          defaultValue: false,
          admin: { description: "Toggle on to expose this announcement to the Send Newsletter endpoint." },
        },
        {
          name: "subject",
          type: "text",
          admin: {
            condition: (_, sibling) => sibling?.send === true,
            description: "Email subject. Defaults to the announcement title if blank.",
          },
        },
        {
          name: "fromName",
          type: "text",
          admin: {
            condition: (_, sibling) => sibling?.send === true,
            description: "From-name. Defaults to RESEND_FROM_NAME env var.",
          },
        },
        {
          name: "customBody",
          type: "richText",
          admin: {
            condition: (_, sibling) => sibling?.send === true,
            description: "Optional email-only override. Leave empty to reuse the modal body.",
          },
        },
        {
          name: "sentAt",
          type: "date",
          admin: {
            condition: (_, sibling) => sibling?.send === true,
            readOnly: true,
            description: "Stamped when /send-newsletter dispatches the blast. Send is idempotent on this field.",
          },
        },
      ],
    },
  ],
};
