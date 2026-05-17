# Incident Response Runbook

_Owner: Thierry. For everything that goes wrong, this is the playbook._

The team is one person. The point of this document is to remove
decision-making from a stressful moment — when something breaks, you
follow the script instead of inventing the response on the fly.

## Severity scale

| Sev | Definition | Response time | Examples |
|---|---|---|---|
| **S1** | User PII exposed OR active financial fraud OR app unsigned/malicious update shipped | Immediate (within 1h) | Database dump leaked; rogue DMG signed; Stripe webhook secret leaked + reuse seen |
| **S2** | Backend down OR payments failing OR auth broken | Same business day | `api.aaavatar.nl` returning 5xx for >5 min; Stripe webhooks 401'ing; Supabase auth refusing sign-ins |
| **S3** | Single feature degraded OR known-bug affecting < 5% of users | Within a week | Magic Cutout intermittently failing; appcast not updating on one cert; non-blocking 502s |
| **S4** | Cosmetic / docs / non-functional | Best effort | Layout regression on Settings screen; typo in privacy policy |

Pick the highest severity that matches. Round up under uncertainty.

## Triage steps (every severity)

1. **Acknowledge**. If a user reported it, reply within the SLA window
   above. Template: "Thanks — investigating, will update by `<HH:MM>`."
2. **Confirm scope**. How many users, which paths, what's the worst
   case? Numbers go in the timeline.
3. **Time-box**. If you haven't found the cause in 30 min, ask for help
   (vendor support, Anthropic, the Vercel community). Don't keep
   guessing.
4. **Stop the bleeding before fixing the root cause**. Revert to last
   known-good deploy via Vercel rollback; flip a feature flag; disable
   a route via Vercel firewall. Investigate root cause after.
5. **Document the timeline as you go** in a new file under
   `docs/security/incidents/YYYY-MM-DD-slug.md`. Even one line per
   action is fine — future-you needs the audit trail.

## S1 procedures (PII / payment / supply-chain)

### Database leak / unauthorized access

1. Rotate `SUPABASE_SERVICE_ROLE_KEY` AND `SUPABASE_JWT_SECRET`
   (runbook: [`secrets-rotation.md`](secrets-rotation.md)).
2. Check Supabase Audit Logs (`Project > Logs > Audit`) for queries
   between the last known-good time and now. Filter by IP.
3. Identify affected users. Pull their `auth.users.id` list.
4. **Notify within 72 hours of awareness** (GDPR Art. 33):
   - Autoriteit Persoonsgegevens: <https://autoriteitpersoonsgegevens.nl/en/contact-dutch-dpa/notify-data-breach>
   - Affected users via the email on file (template: `docs/security/templates/breach-notice.md`)
5. File a post-mortem in `docs/security/incidents/`.

### Stripe webhook secret leaked + reuse seen

1. Stripe dashboard → Developers → Webhooks → roll secret with 24h
   grace.
2. Update `STRIPE_WEBHOOK_SECRET` in Vercel `avatars-api` → redeploy.
3. Audit Stripe events in the leak window for unexpected refunds,
   subscription cancellations, customer modifications.
4. If anything looks crafted: file a "secret leaked" report with Stripe
   so they can force-revoke faster than the 24h grace.

### Rogue Sparkle release (malicious DMG signed under our identity)

This is the worst case. Sparkle's EdDSA verification is per-item, so
a rogue appcast item with a real signature means our signing key was
compromised.

1. **Immediately push an appcast entry with the highest priority +
   shortest cooldown** that points at a clean DMG. Most installed
   versions will pick it up at the next 24h check.
2. Rotate the EdDSA signing key per the
   [secrets-rotation.md → Sparkle EdDSA](secrets-rotation.md#sparkle-eddsa-signing-key)
   runbook. Ship a build with the new public key as soon as possible.
3. Notify users via email + a banner on aaavatar.nl explaining what
   happened and what to do.

## S2 procedures (backend down / payments failing)

### `api.aaavatar.nl` 5xx storm

1. Open Vercel → `avatars-api` → Logs. Filter by status ≥ 500.
2. If recent deploy: **Roll back** via Vercel UI ("Promote to
   production" the previous green deployment).
3. If recent migration: check Supabase Postgres logs for failing
   queries; the new migration may have broken a query under load.
4. If neither: check Replicate / Supabase status pages. Vercel's own
   status page is the last resort.

### Stripe webhooks failing

1. Stripe dashboard → Developers → Webhooks → click the endpoint.
2. If signature errors: `STRIPE_WEBHOOK_SECRET` is stale (recently
   rotated without redeploying Vercel). Re-set the env, redeploy.
3. If 5xx from our function: see "5xx storm" above.
4. Stripe retries for up to 3 days — no immediate need to backfill if
   we recover within that window. After 3 days, run the cron job
   `/api/cron/grant-yearly-credits` manually to backfill ledger
   entries the webhook missed.

### Supabase auth not signing in

1. Supabase dashboard → status (top right). If degraded, wait.
2. Check JWKS endpoint: `curl https://<ref>.supabase.co/auth/v1/.well-known/jwks.json`.
3. Try a manual sign-in in the dashboard's user management. If THAT
   works, the macOS app likely has a stale OAuth callback URL — re-add
   `aaavatar://auth-callback` under Google OAuth.

## S3 procedures (single feature degraded)

1. Add to the standing bug list (`gh issue create`).
2. If it's a Replicate model change: pin a known-good version hash in
   `backend/lib/replicate.ts` (the `MODEL_VERSION` constants document
   the pattern).
3. If it's a vendor outage: post a status note on aaavatar.nl, no need
   for breach-grade comms.

## After every incident

1. **Post-mortem** in `docs/security/incidents/`. Sections: timeline,
   root cause, what worked, what didn't, action items.
2. Update the audit punch-list (`docs/audit-*.md`) if the incident
   surfaced a new finding.
3. If a vendor was the proximate cause, note it in the **last reviewed**
   column of `docs/legal/subprocessors.md` and consider whether the
   vendor is still the right choice.

## Vendor escalation contacts

Keep current — phone numbers and emails change.

| Vendor | Status page | Support email | Notes |
|---|---|---|---|
| Vercel | <https://vercel-status.com> | support@vercel.com | Pro plan = priority queue |
| Supabase | <https://status.supabase.com> | support@supabase.com | Email + dashboard chat |
| Stripe | <https://status.stripe.com> | support@stripe.com | "secret leaked" reports get priority |
| Resend | <https://status.resend.com> | support@resend.com | |
| Replicate | <https://replicatestatus.com> | support@replicate.com | Model availability issues here |
| Upstash | <https://status.upstash.com> | support@upstash.com | |

## Review

This runbook is reviewed annually with the rest of `docs/security/`
(next: **2027-05-18**). Practice runs: optional, recommended after every
S2-or-higher.
