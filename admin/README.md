# Aaavatar Admin (Payload v3)

CMS that drives:
- In-app feature announcements (sign-in pop-up modal in the macOS app)
- "NEW" badges on registered components
- Email newsletters via Resend

## Quick start

```bash
cd admin
cp .env.example .env
# fill in DATABASE_URL, PAYLOAD_SECRET, S3_*, SUPABASE_*, RESEND_*
npm install
npm run dev
# admin at http://localhost:3001/admin
```

On first run Payload creates its tables in the `payload` Postgres schema
and prompts you to create the first admin user via the dashboard.

## Editor flow

1. **Create an Announcement** — title, slug, hero image, body, optional CTA.
2. **Pick frequency** — `once` is the most common (next sign-in, never again).
3. **Pick audience** — `all`, `freeUsers`, `proUsers`, or `specificEmails`.
4. **(Optional) badge campaign** — add rows under `badgeTargets` referencing
   IDs from the `badge-components` collection.
5. **(Optional) newsletter** — toggle `newsletter.send`, set subject/body,
   POST to `/api/send-newsletter` with `{ announcementId, testMode: true,
   testEmail: "you@x.com" }` to preview, then again without `testMode` to
   blast.
6. **Set `publishedAt`** — once non-null and in the past, the macOS app
   will see it on next sign-in.

## Deploy

Deployed as its own Vercel project (`avatar-admin`) at
`admin.aaavatar.nl`. See `docs/announcements-infra.md` in the repo root
for one-time setup steps (DNS, Resend domain, Supabase Storage bucket).
