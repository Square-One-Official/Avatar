# Subprocessors

_Last updated: 17 May 2026._

Square One (Netherlands) is the data controller for Avatar / Aaavatar. The
companies below act as **processors** on our instructions under GDPR Art. 28.
The same list is published in plain language in the public [Privacy Policy](../../website/privacy.md);
this document is the operator-facing version with addresses, contract URLs,
and DPA status used for the [DPA tracking](./dpa-tracking.md) workflow.

| # | Subprocessor | Legal entity | Service used | Personal data shared | Hosting region | DPA |
|---|---|---|---|---|---|---|
| 1 | **Supabase** | Supabase Inc., 970 Toa Payoh North, #07-04, Singapore | Auth, Postgres, Storage | Account email, user ID, Stripe customer ID, subscription tier, credit ledger, magic-cutout upload (briefly during processing) | EU (`eu-central-1`) | [supabase.com/legal/dpa](https://supabase.com/legal/dpa) |
| 2 | **Stripe** | Stripe Payments Europe Ltd., 1 Grand Canal Street Lower, Dublin 2, Ireland | Subscription billing | Email, payment instrument, billing address, IP, country | EU + US | [stripe.com/legal/dpa](https://stripe.com/legal/dpa) |
| 3 | **Replicate** | Replicate Inc., 548 Market St #75636, San Francisco, CA 94104, USA | AI inference (Magic Cutout, Colorize, Fill-Body) | The single image submitted with the request; retained only for the request lifetime per Replicate's [data policy](https://replicate.com/privacy) | US | Standard Replicate Terms include a DPA addendum |
| 4 | **Resend** | Resend, Inc., 2261 Market Street #4733, San Francisco, CA 94114, USA | Transactional + announcement email delivery | Email address, rendered email body | EU sending region | [resend.com/legal/dpa](https://resend.com/legal/dpa) |
| 5 | **Vercel** | Vercel Inc., 340 S Lemon Ave #4133, Walnut, CA 91789, USA | Hosting of `api.aaavatar.nl` and `admin.aaavatar.nl` | Request logs (IP, timestamp, path) | EU edge regions (`cdg1`, `fra1`) | [vercel.com/legal/dpa](https://vercel.com/legal/dpa) |
| 6 | **Upstash** | Upstash Inc., 340 S Lemon Ave #1042, Walnut, CA 91789, USA | Serverless Redis for rate limiters (`/v1/cutout`, magic-link, anon-account, anon-checkout) | The rate-limit key (device fingerprint UUID or IP) for a few minutes | EU (`fra1`) | [upstash.com/dpa](https://upstash.com/dpa) |
| 7 | **GitHub** | GitHub, Inc., 88 Colin P. Kelly Jr. Street, San Francisco, CA 94107, USA | Hosting of the Sparkle appcast and source repository | IP and HTTP metadata of update checks | Global | [github.com/data-protection-agreement](https://github.com/customer-terms/github-data-protection-agreement) |
| 8 | **Google (Drive API + Sign-In)** | Google Ireland Ltd., Gordon House, Barrow Street, Dublin 4, Ireland | Optional shared workspaces — data stays in the user's own Drive | n/a (Square One never receives the workspace content) | Google global | [cloud.google.com/terms/data-processing-addendum](https://cloud.google.com/terms/data-processing-addendum) |
| 9 | **Apple** | Apple Distribution International Ltd., Hollyhill Industrial Estate, Cork, Ireland | App notarization, Push (none used), App Store distribution (if/when MAS build ships) | Bundle identifier, build version, crash logs (only if user opts in via Apple's "Share with Developers") | Apple global | Apple Developer Program License Agreement, Schedule 2 |

## Changes

Any addition of a new subprocessor will be announced at least 14 days in advance via:

- An update to this file in `main` (commit history is the audit trail);
- A note in the next product newsletter to opted-in users.

Existing subscribers can object to the change by emailing info@squareone.nl
within those 14 days; the only remedy we can offer is cancellation of the
Pro subscription (the new subprocessor may be essential to the feature
being delivered, in which case we can't keep operating without it).
