# Information Security Policy

_Owner: Thierry Emmery (Square One). Reviewed annually. This revision:
2026-05-18._

This document is the standing security policy for the Avatar / Aaavatar
product. It's intentionally short because the team is one person — the
goal is operator-readable promises, not a checkbox doc.

## 1. Scope

Covers:

- The macOS app `Avatar` distributed via Sparkle DMG + (planned) Mac App Store.
- The backend at `api.aaavatar.nl` (Vercel project `avatars-api`).
- The admin CMS at `admin.aaavatar.nl` (Vercel project `avatar-admin`).
- Supporting infrastructure: Supabase (Postgres / Auth / Storage),
  Stripe (billing), Resend (email), Replicate (AI inference),
  Upstash (rate-limit Redis), Vercel (compute + CDN), GitHub
  (source code + Sparkle appcast — being sunset per audit HIGH #10).

Out of scope: end-user devices (the user's own Mac, network, accounts).

## 2. Classification

Three tiers, applied per-table / per-storage-bucket:

| Tier | Examples | Handling |
|---|---|---|
| **PII** | `auth.users`, `public.users`, `subscriptions`, `credit_ledger`, `device_grants`, `newsletter-unsubscribes` | Service-role / scoped role only. Never logged in plaintext. |
| **payment** | `subscriptions.stripe_customer_id`, Stripe customer records (held by Stripe), `credit_ledger.ref` | Same as PII plus 7-year retention (Dutch tax law). |
| **public** | `appcast.xml`, `announcements`, `badge-components`, signed-URL paths | Routable on a CDN. No retention concern. |

Full table-by-table map: [`backend/sql/README.md`](../../backend/sql/README.md).

## 3. Access controls

- **Production code**: only the project owner has Vercel admin rights on
  both projects. CI pushes via the `vercel deploy` integration use a
  scoped token visible in Vercel team settings.
- **Database**: Supabase project owner role is the only superuser.
  The backend uses `SUPABASE_SERVICE_ROLE_KEY` (RLS-bypass scope). The
  admin uses the `payload_app` Postgres role, scoped to the `payload`
  schema + `newsletter_cohorts` view only — see audit CRITICAL #1 +
  HIGH #12.
- **Admin UI**: TOTP gate via `ADMIN_TOTP_SECRET` (audit HIGH #11). The
  Payload password is the second factor.
- **Stripe**: project owner has the live API key. Webhook events arrive
  signature-verified.
- **macOS app code-signing**: Developer ID identity stored locally on
  the build Mac, backed up in 1Password ("Avatar / Signing").

## 4. Encryption

- **At rest**: Supabase Postgres + Storage are encrypted by Supabase
  (AES-256). The macOS app encrypts its on-disk auth blob via CryptoKit
  AES-GCM with a Keychain-stored key (audit HIGH #7).
- **In transit**: HTTPS-only. ATS strict-mode on the macOS client
  (audit CRITICAL #4) plus certificate pinning for `api.aaavatar.nl`.

## 5. Secrets handling

- All production secrets live in Vercel project env (encrypted at rest
  by Vercel).
- Rotation cadence + runbooks: [`docs/security/secrets-rotation.md`](secrets-rotation.md).
- Never committed: `.env.local` files are gitignored. Audit-time
  scanning runs through `npm audit` weekly via Dependabot.
- If a secret leaks in a public commit: rotate within 1 hour, follow
  the runbook in `secrets-rotation.md` § Incident response.

## 6. Vulnerability management

- **Dependencies**: Dependabot scans `admin/` and `backend/` weekly
  (`.github/dependabot.yml`). Patch + minor PRs land within a week;
  major upgrades reviewed individually.
- **Pre-merge gates**: `.github/workflows/ci.yml` runs `tsc --noEmit`
  on both projects + `npm audit --audit-level=high --production` so a
  high-severity vuln fails the build.
- **Annual review** of this policy, the secrets-rotation table, and
  the subprocessor list.

## 7. Change management

- **All changes via git**. PRs require a clean CI run (typecheck +
  audit + appcast lint). The audit history is `git log`.
- **Releases**: signed DMG + EdDSA-signed Sparkle update items via
  `scripts/release.sh`. Notarized + stapled.
- **Migrations**: numbered SQL files in `backend/sql/`, applied
  manually in the Supabase SQL editor. Each migration's header explains
  what it does and what depends on it; revert path documented inline
  when non-obvious.

## 8. Logging & monitoring

- **Backend**: Vercel logs request path + status code + IP for ~24h.
  Sensitive paths (signed URLs, JWTs) are redacted in app-level logs —
  see audit MEDIUM #21.
- **Admin**: Vercel logs + Payload's own admin-action UI.
- **Stripe / Supabase / Resend / Upstash**: each vendor's dashboard
  is the source of truth; logs retained per vendor SLA (typically 30d
  for Supabase, 90d+ for Stripe).
- **No centralised SIEM today** — Vercel + Supabase dashboards are
  the operator-facing surface. If volume grows past one person's
  ability to triage, route via a log drain (Axiom / Better Stack).

## 9. Incident response

See [`docs/security/incident-response.md`](incident-response.md) for
the triage runbook (severity scoring, vendor escalation paths,
user-comms templates).

## 10. Data protection (GDPR)

- **Square One** (Netherlands) is the data controller. Vendors listed
  in [`docs/legal/subprocessors.md`](../legal/subprocessors.md) act as
  processors under signed DPAs.
- **Legal bases** (Art. 6) per data category are documented in the
  public privacy policy: [`website/privacy.md`](../../website/privacy.md).
- **Right to erasure** (Art. 17): `DELETE /v1/account` on the backend
  wipes the auth user (cascades to subscriptions, credit ledger,
  device counters), cancels active Stripe subscriptions, and sweeps
  the user's `cutout-uploads` Storage prefix. Stripe customer +
  invoice records are retained for 7 years under Dutch tax law and the
  Art. 6(1)(c) legal-obligation basis.
- **DPIA**: [`docs/legal/dpia-image-processing.md`](../legal/dpia-image-processing.md)
  covers the cloud AI features (Magic Cutout, Colorize, Fill-Body) which
  process user-supplied portraits via Replicate (US).

## 11. Review

This document is reviewed annually (next: **2027-05-18**). Material
changes (new subprocessor, new data category, change to default
encryption posture) trigger an off-cycle review.
