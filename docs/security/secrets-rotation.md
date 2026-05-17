# Secrets rotation policy

_Audit HIGH #14. Owner: Thierry. Cadence: every 90 days, plus immediately
when a secret leaks (commit, log line, deck screenshot, ex-collaborator)._

The Aaavatar stack has roughly a dozen long-lived secrets across two
Vercel projects, Supabase, Stripe, Resend, Replicate, and Upstash. None
of them currently rotate; this document captures the standing rotation
schedule and the operator runbook for each.

## Schedule

| Secret | Where it lives | Cadence | Last rotated | Next due |
|---|---|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Vercel `avatars-api` (and `avatar-admin` until HIGH #12) | 90 days | n/a | _set on first rotation_ |
| `SUPABASE_JWT_SECRET` | Vercel `avatars-api` | 180 days | n/a | _set on first rotation_ |
| Supabase database password (`payload_app`) | Vercel `avatar-admin` (`PAYLOAD_DATABASE_URL`) | 90 days | n/a | _set on first rotation_ |
| `STRIPE_SECRET_KEY` | Vercel `avatars-api` | 90 days | n/a | _set on first rotation_ |
| `STRIPE_WEBHOOK_SECRET` | Vercel `avatars-api` | rotated when webhook URL changes | n/a | _on next webhook change_ |
| `RESEND_API_KEY` | Vercel `avatar-admin` | 90 days | n/a | _set on first rotation_ |
| `REPLICATE_API_TOKEN` | Vercel `avatars-api` | 90 days | n/a | _set on first rotation_ |
| `PAYLOAD_SECRET` | Vercel `avatar-admin` | 365 days | n/a | _set on first rotation_ |
| `PAYLOAD_API_KEY` (Payload Users record) | Vercel `avatars-api` | 90 days | n/a | _set on first rotation_ |
| `CRON_SECRET` | Vercel `avatars-api` | 180 days | n/a | _set on first rotation_ |
| `UPSTASH_REDIS_REST_TOKEN` | Vercel `avatars-api` + `avatar-admin` | 180 days | n/a | _set on first rotation_ |
| `UNSUBSCRIBE_SIGNING_SECRET` | Vercel `avatars-api` + `avatar-admin` | 365 days | n/a | _set on first rotation_ |
| `ADMIN_TOTP_SECRET` | Vercel `avatar-admin` | only on device loss | n/a | _on event_ |
| `ADMIN_MFA_SIGNING_SECRET` | Vercel `avatar-admin` | 180 days | n/a | _set on first rotation_ |
| Sparkle `SUPublicEDKey` / signing key | `project.yml` + local Keychain (private half) | annually | n/a | _set on first rotation_ |

Add a row whenever a new secret is introduced; update the **Last rotated**
column every time you rotate. The audit checks this table during the
annual readiness review.

## Runbooks

### Generic Vercel env var

Most rotations are the same shape:

1. Generate a fresh value: `openssl rand -base64 48` for arbitrary
   secrets, or use the provider's "rotate" button (Stripe, Resend,
   Supabase, Replicate, Upstash all have one).
2. **Add the new value alongside the old one** so both still work
   briefly. For env vars this means: in Vercel, add a *new* env var name
   like `STRIPE_SECRET_KEY_NEXT`, set the new value, redeploy a preview
   that reads from the new name, smoke-test, then promote.
3. For provider-issued keys (Stripe, Supabase, Resend, Replicate): the
   provider lets multiple keys be active at once. Use that overlap
   window to update Vercel + redeploy before invalidating the old key.
4. Once the new value is live in production and verified, delete the
   old key in the provider AND remove the old env var in Vercel.
5. Update **Last rotated** in this table.

### Stripe webhook secret

`STRIPE_WEBHOOK_SECRET` is *per webhook endpoint* — rotating it means:

1. Stripe dashboard → Developers → Webhooks → click your endpoint →
   "Roll secret" with a 24-hour grace.
2. Add the new value as `STRIPE_WEBHOOK_SECRET` in Vercel, redeploy.
3. After the grace, Stripe drops the old secret automatically.

### Supabase service role / JWT secret

⚠ Service-role rotation is **disruptive** — every backend instance
that holds the old key starts 401-ing the moment Supabase rotates.
Coordinate this:

1. Supabase dashboard → Settings → API → "Reveal & rotate" the service
   role key. Capture the new value.
2. Update `SUPABASE_SERVICE_ROLE_KEY` in Vercel `avatars-api` (and
   `avatar-admin` until HIGH #12 lands) → click "Redeploy" so the new
   functions read the new key.
3. **Do NOT click the Supabase dashboard's revoke button until both
   Vercel deployments report green** — the old key is implicitly valid
   until the dashboard explicitly revokes.

JWT secret rotation invalidates every existing user session — every
signed-in macOS app forces a re-auth. Plan a low-traffic window.

### Payload API key (`PAYLOAD_API_KEY`)

The key lives on a Users record inside Payload itself:

1. Sign in to admin.aaavatar.nl → Users collection → your "API Keys"
   user → toggle `enableAPIKey` off and on to mint a new key (or use
   the regenerate action in Payload's UI).
2. Copy the new key value into Vercel `avatars-api` →
   `PAYLOAD_API_KEY` → redeploy.
3. Old key becomes invalid the moment Payload writes the new one.
4. Smoke-test announcements (`curl https://api.aaavatar.nl/v1/announcements/pending`).

### Sparkle EdDSA signing key

This is the riskiest rotation because the *public* half is baked into
shipped builds (`SUPublicEDKey` in `project.yml`). A rotation requires:

1. Generate a new key pair with `sign_update --generate-keys` (Sparkle
   ships the CLI in its release artifact).
2. Add the **new** public key to `project.yml` `SUPublicEDKey` and
   ship a release **signed by the old private key**. Users update to a
   build that trusts both old and new keys.
3. Wait for adoption (`appcast.xml` analytics or a couple of release
   cycles — typically 30 days).
4. Switch the signing identity over: future releases signed by the new
   private key. Drop the old public key from `project.yml` once you're
   confident every active install has updated.
5. Store the new private key in 1Password ("Avatar / Sparkle"). Never
   commit it.

If the **private** half leaks, you have no clean fix — the attacker
can sign a malicious appcast that passes Sparkle's verification on
existing installs. The only mitigation is to ship a build that trusts a
new public key only and hope users update before the leak is weaponised.

## Incident response: secret leaked publicly

If a secret lands in a public commit / log / screenshot:

1. **Rotate immediately**, then audit Stripe / Supabase / Resend access
   logs for the rotation window.
2. For Stripe specifically: file a "secret leaked" report in the
   dashboard so Stripe can issue a faster forced-revoke if needed.
3. `git filter-repo` or `git push --force` are NOT sufficient — the
   secret is already on someone's `git fetch` or in GitHub's
   compressed-pack history. Assume the secret is burned the moment it
   lands in any tree GitHub has seen.

## Review

Once a year, walk this table and:
- Confirm every secret is still in use (delete unused rows).
- Confirm every secret has rotated within its window.
- Update the table with new secrets added since last review.

Next annual review: **2027-05-17**.
