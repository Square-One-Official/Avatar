# Announcement system — one-time infra setup

Run through this once before the new code can light up. Each step is
independent until called out.

## 1. Supabase: storage bucket

Open the Supabase dashboard → Storage → New bucket.

- Name: `announcement-media`
- Public: **yes** (the macOS app fetches images directly)
- File size limit: 10 MB
- Allowed MIME types: `image/png`, `image/jpeg`, `image/webp`, `image/gif`

Then under Project Settings → Storage → S3 connection, copy:

- `S3_ENDPOINT` (e.g. `https://<ref>.storage.supabase.co/storage/v1/s3`)
- `S3_REGION`
- Generate an access key pair → `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`

## 2. Supabase: announcement_seen table

In the Supabase SQL editor, run [`backend/sql/007_announcements.sql`](../backend/sql/007_announcements.sql).
It creates `public.announcement_seen` and the empty `payload` schema
(Payload owns its own tables in there).

## 3. Resend: domain verification

1. Sign up at resend.com (or log in if you already have an account).
2. Domains → Add domain → `aaavatar.nl`.
3. At your registrar, add the three TXT records Resend provides
   (SPF, DKIM, DMARC).
4. Wait for verification (~5–30 min). Domain status flips to "Verified".
5. API Keys → Create API key, scope `Sending access` for `aaavatar.nl`.
   Save it as `RESEND_API_KEY`.

## 4. Vercel: new project for admin app

1. `cd admin && vercel link` (or import `/admin` as a new project in the
   Vercel dashboard, root directory = `admin`).
2. Custom domain: `admin.aaavatar.nl` (Vercel will issue an SSL cert).
3. At your DNS provider, add CNAME `admin` → `cname.vercel-dns.com`.
4. Set environment variables (Production + Preview):

   ```
   PAYLOAD_SECRET=<32 random bytes>
   PAYLOAD_PUBLIC_SERVER_URL=https://admin.aaavatar.nl
   DATABASE_URL=postgresql://...   # Supabase pooler, ?schema=payload
   RESEND_API_KEY=re_xxx
   RESEND_FROM_EMAIL=news@aaavatar.nl
   RESEND_FROM_NAME=Aaavatar
   SUPABASE_URL=https://<ref>.supabase.co
   SUPABASE_SERVICE_ROLE_KEY=eyJ...
   S3_ENDPOINT=https://<ref>.storage.supabase.co/storage/v1/s3
   S3_REGION=eu-central-1
   S3_ACCESS_KEY_ID=...
   S3_SECRET_ACCESS_KEY=...
   S3_BUCKET=announcement-media
   ```

5. Deploy. First request will run Payload's bootstrap (table creation
   in the `payload` schema) and route you through the "create first
   admin user" flow at `https://admin.aaavatar.nl/admin/create-first-user`.

## 5. Backend (api.aaavatar.nl): Payload API key

1. In the Payload admin (after step 4), Users → Create.
   - Email: `backend-bot@aaavatar.nl` (any address; not used for login)
   - `enableAPIKey: true` → generates a key
2. Copy the key.
3. Add to the `avatars-api` Vercel project envs:

   ```
   PAYLOAD_API_URL=https://admin.aaavatar.nl/api
   PAYLOAD_API_KEY=<the generated key>
   ```

4. Redeploy the backend.

## 6. Seed the badge-component registry

In Payload admin → Badge Components → Create one row per ID listed in
[`Avatar/Services/AnnouncementService.swift`](../Avatar/Services/AnnouncementService.swift)
under `enum BadgeComponent`:

| componentId    | label               |
|----------------|---------------------|
| magic-cutout   | Magic Cutout button |
| fill-body      | Fill in Body button |
| colorize       | Colourise button    |
| export-sheet   | Export sheet entry  |
| backgrounds    | Backgrounds picker  |

Add new IDs whenever you add `.newBadge("...")` somewhere new.

## 7. Smoke test

1. Sign in to the macOS app with `thierry@squareone.nl`.
2. In Payload admin → Announcements → Create:
   - Title: "Test announcement"
   - Slug: `test-2026-05`
   - Body: "If you can read this in the app, the wiring works."
   - Audience: Specific emails → `thierry@squareone.nl`
   - Frequency: Show once
   - Publish: now
3. Sign out + back in on the macOS app — the modal should appear with
   your text.
4. Dismiss → check `public.announcement_seen` has a row.
5. Sign out + back in again → modal does NOT reappear.

## 8. Before any non-test newsletter blast

- Wire up unsubscribe URLs in `admin/src/endpoints/sendNewsletter.ts`
  (currently `unsubscribeUrl: undefined`). Required for CAN-SPAM /
  GDPR compliance. Cheapest approach: a `/v1/unsubscribe?token=...`
  endpoint on the backend that flips an `unsubscribed_at` column on
  `auth.users` (via a side table, since you can't alter `auth.users`).
- Add a one-time consent check at sign-up if you want to be strict
  about marketing-email opt-in vs. transactional.

These are flagged in the plan as "out of scope for v1" — track them
before the first real send.
