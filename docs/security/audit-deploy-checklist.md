# Audit remediation — deploy checklist

_What the operator (Thierry) needs to do AFTER merging this branch.
Items are ordered so each step has a clean rollback if the next step
fails. Tick them off in order — don't skip ahead._

The branch closes the entire 31-item audit from
[`/Users/thierry/.claude/plans/audit-the-code-base-effervescent-dongarra.md`](../../.claude/plans/audit-the-code-base-effervescent-dongarra.md)
plus the ISO/SOC documentation gap. Most changes are pure code +
documentation, but several touch live infrastructure and need manual
out-of-band work to take effect.

## 1. Supabase — apply SQL migrations

Run in the Supabase SQL editor for the production project, **in this
order**. Each migration is idempotent (re-run safe) but they depend on
the ones before them.

- [ ] [`008_payload_scoped_role.sql`](../../backend/sql/008_payload_scoped_role.sql)
  Creates the `payload_app` Postgres role, re-homes ownership of the
  `payload` schema to it, walls it off from `public.*` / `auth.*`.
- [ ] After 008 lands, set a password for the role:
  ```sql
  alter role payload_app with password '<openssl rand -hex 32>';
  ```
  Save the password in 1Password ("Avatar / Supabase / payload_app").
- [ ] [`009_current_credits_fix.sql`](../../backend/sql/009_current_credits_fix.sql)
  Fixes the multi-active-subscription edge case in `current_credits()`.
- [ ] [`010_newsletter_cohorts_view.sql`](../../backend/sql/010_newsletter_cohorts_view.sql)
  Materialised view + SECURITY DEFINER refresh function.
- [ ] [`011_free_import_counter_merge.sql`](../../backend/sql/011_free_import_counter_merge.sql)
  Account/device counter merge on first sign-in per device.

## 2. Vercel — `avatars-api` (backend) env vars

Open the Vercel project, Settings → Environment Variables. Add to
**Production + Preview**:

- [ ] `UNSUBSCRIBE_SIGNING_SECRET` — `openssl rand -base64 48`.
  Note the value; the admin needs the SAME value (step 4).
- [ ] `PAYLOAD_API_URL` — `https://admin.aaavatar.nl/api`.
- [ ] `PAYLOAD_API_KEY` — generate from the Payload admin UI by
  toggling `enableAPIKey` on a Users record after step 3 below.

Already configured (don't touch unless rotating):
`SUPABASE_*`, `STRIPE_*`, `RESEND_*`, `REPLICATE_API_TOKEN`,
`UPSTASH_REDIS_REST_*`, `CRON_SECRET`.

Redeploy after adding.

## 3. Vercel — `avatar-admin` (admin) env vars

In the admin project's Vercel settings, add to **Production + Preview**:

- [ ] `PAYLOAD_DATABASE_URL` —
  `postgresql://payload_app:<password>@db.<ref>.supabase.co:5432/postgres?schema=payload`
  (the password from step 1, the project ref from your Supabase
  dashboard).
- [ ] `ADMIN_TOTP_SECRET` + `ADMIN_MFA_SIGNING_SECRET` — generate with:
  ```bash
  cd admin
  node scripts/setup-mfa.mjs
  ```
  Paste the base32 secret and signing secret into Vercel. Scan the
  printed `otpauth://…` URI into 1Password / Authy / Google
  Authenticator.
- [ ] `UNSUBSCRIBE_SIGNING_SECRET` — same value as step 2. They must
  match byte-for-byte or every unsubscribe click returns 400.
- [ ] `UPSTASH_REDIS_REST_URL` + `UPSTASH_REDIS_REST_TOKEN` — same
  values the backend uses (the prefixes prevent key collisions).

Once these land, redeploy. Then **remove** the old env vars that
are no longer needed:

- [ ] Remove `SUPABASE_URL` from the admin project.
- [ ] Remove `SUPABASE_SERVICE_ROLE_KEY` from the admin project.
- [ ] Remove the legacy `DATABASE_URL` from the admin project (the
  new `PAYLOAD_DATABASE_URL` is the canonical source; the fallback in
  `payload.config.ts` keeps things working during the rollover, but
  production shouldn't ever fall back).

## 4. First admin visit

- [ ] Open `https://admin.aaavatar.nl/admin`. You should be redirected
  to `/mfa`.
- [ ] Enter the current 6-digit TOTP code from your authenticator.
- [ ] Land on Payload's password login. Sign in.
- [ ] Open Users → your record → toggle `enableAPIKey`. Copy the key.
- [ ] Paste the key into the backend Vercel project as
  `PAYLOAD_API_KEY` (step 2). Redeploy backend.

## 5. Smoke tests

- [ ] `curl -i https://api.aaavatar.nl/appcast.xml` — expect `200`,
  `content-type: application/xml`, body starts with `<?xml`. (audit #10)
- [ ] `curl -i -X POST https://api.aaavatar.nl/v1/account/resend-magic-link`
  → expect `400 missing_device_fingerprint`. Add a bogus fingerprint
  and hit 5 times — expect a `429 rate_limited` somewhere in the
  burst. (audit #2)
- [ ] `curl -i -X DELETE https://api.aaavatar.nl/v1/account` without
  auth → expect `401`. With auth but without
  `X-Confirm-Delete: yes` → expect `400`. (audit right-to-erasure)
- [ ] In the admin, save an Announcement. Open the new `audit-log`
  collection in the sidebar — see a row for your save. (audit #24)
- [ ] Trigger a test newsletter send (`testMode: true`) to your own
  inbox. Inspect the email source — `List-Unsubscribe` header present,
  footer link points to `api.aaavatar.nl/v1/unsubscribe?token=…`.
  Click it; should land on the dark confirmation page. (audit #15)

## 6. macOS app — ship a new build

The new build needs to ship before users start hitting any of the new
endpoints. Run:

```bash
./scripts/release.sh
```

The script now does the additional step of mirroring `appcast.xml` →
`backend/api/_appcast.xml`. Don't forget to commit BOTH files.

- [ ] Verify the new build still receives updates from BOTH legacy
  GitHub raw + new `api.aaavatar.nl/appcast.xml` paths. The legacy
  path keeps working for older installs until they update.
- [ ] After 4–6 weeks of new-build adoption, consider sunsetting the
  GitHub raw path by stopping the commit-to-repo-root in
  `release.sh` (track this on the calendar).

## 7. Legal / paperwork (no urgency, but should land within 30 days)

- [ ] Open a Supabase support ticket using the template at
  [`docs/legal/supabase-eu-residency.md`](../legal/supabase-eu-residency.md).
  File the response under `docs/legal/dpa/`.
- [ ] Click through the DPAs in
  [`docs/legal/dpa-tracking.md`](../legal/dpa-tracking.md) for each
  vendor marked ☐ todo. Save receipts under `docs/legal/dpa/`.
- [ ] Publish the updated
  [`website/privacy.md`](../../website/privacy.md) to aaavatar.nl. The
  rewrite is honest about the cloud backend's existence and the
  Replicate (US) transfer — old promises ("we don't run a backend")
  are gone.

## 8. Calendar reminders

Drop these into your calendar so they don't drift:

- [ ] **2026-08-17** — first 90-day secret rotation review
  ([`secrets-rotation.md`](secrets-rotation.md)).
- [ ] **2027-05-18** — annual review of
  [`docs/security/policy.md`](policy.md),
  [`incident-response.md`](incident-response.md),
  [`docs/legal/dpia-image-processing.md`](../legal/dpia-image-processing.md),
  [`docs/legal/subprocessors.md`](../legal/subprocessors.md),
  [`docs/legal/dpa-tracking.md`](../legal/dpa-tracking.md).

## Rollback notes

If anything in step 1 (SQL) goes sideways, every migration is forward-
only but each is idempotent — re-running won't compound damage. To
revert to the pre-audit schema in an emergency:

```sql
-- Worst-case revert (would orphan the admin temporarily):
drop function if exists public.refresh_newsletter_cohorts();
drop materialized view if exists public.newsletter_cohorts;
drop table if exists public.device_user_merges;
-- DO NOT drop the payload schema or payload_app role — that
-- would wipe the announcements collection.
```

Vercel rollbacks are one click per project in the deployments list.

## Status

- [ ] Section 1 (Supabase migrations) complete
- [ ] Section 2 (backend env) complete
- [ ] Section 3 (admin env) complete
- [ ] Section 4 (first admin visit) complete
- [ ] Section 5 (smoke tests) complete
- [ ] Section 6 (macOS release) complete
- [ ] Section 7 (legal paperwork) complete
- [ ] Section 8 (calendar) complete

When all checked, this branch is fully deployed. File this document under
`docs/security/incidents/2026-05-18-audit-rollout-complete.md` as a
record of the rollout.
