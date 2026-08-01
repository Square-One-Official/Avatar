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

## Granting Pro without payment (`pro-access`)

The **Pro access** collection is the Pro list: accounts that get Pro
without a Stripe subscription. Add the address the person signs in with;
it takes effect within a minute (the backend caches the list for 60s) and
needs no deploy. An entry for an address that never signs up simply does
nothing until it does.

- **Access = Pro** (default) — a comped subscription. Every Pro gate
  opens and the account gets `monthlyCredits` (default 200) per calendar
  month. Cloud actions cost credits exactly as they do for a paying
  subscriber, so the Replicate bill stays bounded. The allowance is a
  top-up, not a stack: unspent credits don't roll over.
- **Access = Unlimited** — internal/dev only. Every credit check
  bypassed, plus the Advanced model picker in the app. Keep this for our
  own accounts.

Revoke by unchecking **active** (keeps the record) or by setting
**expiresAt**. Every change is written to the audit log.

Two things deliberately don't go through this collection: writes are
admin-session-only, so the backend's Payload API key can read the list but
never add to it; and `DEV_UNLIMITED_EMAILS` on the avatars-api Vercel
project still grants Unlimited, as the break-glass path for when this CMS
is unreachable.

## Deploy

Deployed as its own Vercel project (`avatar-admin`) at
`admin.aaavatar.nl`. See `docs/announcements-infra.md` in the repo root
for one-time setup steps (DNS, Resend domain, Supabase Storage bucket).

## MFA on the admin (TOTP)

The admin is gated behind a TOTP step before Payload's password login —
real 2FA (audit HIGH #11). Browser flow:

    GET /admin/*  →  no mfa cookie  →  redirect /mfa
    POST /api/mfa/verify  →  TOTP check  →  set mfa cookie
    GET /admin/*  →  Payload's password login

Machine-to-machine requests using `Authorization: users API-Key …` (the
backend calling Payload's REST API) bypass the TOTP gate — Payload's own
auth still applies to those.

One-time setup:

1. Generate the secrets:
   ```bash
   node scripts/setup-mfa.mjs
   ```
   This prints `ADMIN_TOTP_SECRET`, `ADMIN_MFA_SIGNING_SECRET`, and an
   `otpauth://…` URI for your authenticator app (1Password, Authy, Google
   Authenticator, etc.). Scan the URI or paste the secret manually with
   SHA-1 / 6 digits / 30 s.
2. Add both env vars to the `avatar-admin` Vercel project for
   **Production + Preview**, then redeploy.
3. Visit `https://admin.aaavatar.nl/admin` — you'll land on `/mfa`. Enter
   the current 6-digit code. The cookie lasts 8 hours; Payload's session
   sits on top.

If you ever need to revoke a stolen device, rotate `ADMIN_MFA_SIGNING_SECRET`
in Vercel — every issued cookie immediately becomes invalid.

## Database role (scoped `payload_app`)

Payload connects through a Postgres role whose privileges are confined to
the `payload` schema, so an admin compromise can't read `public.users`,
`subscriptions`, etc. (audit CRITICAL #1).

One-time rollover, run in the Supabase SQL editor as the project owner:

1. Apply [`backend/sql/008_payload_scoped_role.sql`](../backend/sql/008_payload_scoped_role.sql)
   — creates the role, reassigns ownership of the `payload` schema, and
   walls it off from `public.*` / `auth.*`.
2. Set a password (kept out of git on purpose):
   ```sql
   alter role payload_app with password '<32 random bytes>';
   ```
3. Build the connection string:
   ```
   postgresql://payload_app:<password>@db.<project>.supabase.co:5432/postgres?schema=payload
   ```
   Use the direct (5432) port — pgbouncer's transaction-mode pooler breaks
   Payload migrations.
4. In the Vercel `avatar-admin` project, set `PAYLOAD_DATABASE_URL` for
   **Production + Preview**. Redeploy and verify the admin loads + can
   save an Announcement.
5. Once verified, remove the legacy `DATABASE_URL` env var (it's still
   honoured as a fallback in `payload.config.ts`, but should not be set in
   production any more).

**Service-role decoupling is complete (audit CRITICAL #1 + HIGH #12).**
Newsletter cohort resolution now reads from the
`public.newsletter_cohorts` materialised view via the scoped
`payload_app` connection; the SECURITY DEFINER refresh function in
[`010_newsletter_cohorts_view.sql`](../backend/sql/010_newsletter_cohorts_view.sql)
keeps it fresh on every send. Once that migration is applied, remove
`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` from the admin Vercel
project.
