# DPA tracking

Operator-facing checklist of which Data Processing Agreements have been
accepted / signed and where the signed copies live. Audit HIGH #15.

The signed PDFs themselves don't need to be in the public repo — keep
them in `docs/legal/dpa/` (gitignored) or in 1Password under "Avatar /
Legal". This file is the lightweight tracker.

## Status

| # | Subprocessor | Action required | Status | Signed copy | Last reviewed |
|---|---|---|---|---|---|
| 1 | Supabase | Accept DPA in dashboard → Settings → Legal | ☐ todo | — | — |
| 2 | Stripe | Auto-included in Stripe Services Agreement (no separate signature) | ☑ implicit | n/a | 2026-05-17 |
| 3 | Replicate | DPA addendum part of Terms; reach out to legal@replicate.com if a counter-signed copy is needed | ☐ request signed copy | — | — |
| 4 | Resend | Accept DPA at resend.com/legal/dpa (link signs via DocuSign) | ☐ todo | — | — |
| 5 | Vercel | Accept DPA in Team Settings → Legal | ☐ todo | — | — |
| 6 | Upstash | Accept DPA at upstash.com/dpa | ☐ todo | — | — |
| 7 | GitHub | Auto-included in customer terms; counter-signed copy available on request | ☑ implicit | n/a | 2026-05-17 |
| 8 | Google | DPA accepted as part of Google Cloud Platform sign-up + Google Workspace agreement | ☑ implicit | n/a | 2026-05-17 |
| 9 | Apple | DPA covered by ADP Schedule 2 | ☑ implicit | n/a | 2026-05-17 |

## Workflow

1. For each row marked **todo**, follow the link in [`subprocessors.md`](./subprocessors.md), sign the DPA in the vendor's portal.
2. Download the executed copy (PDF). Save it as `docs/legal/dpa/<vendor>-<YYYYMMDD>.pdf` (the directory is gitignored).
3. Update the row above: change ☐ to ☑, fill the **Signed copy** column with the filename, set **Last reviewed** to today.
4. Re-review annually (every May) or whenever a vendor materially changes their DPA — they typically notify by email.

## Counter-signed copies that need humans

A few vendors only counter-sign on request. Track outstanding requests
here so they don't get lost in inbox triage:

- _none right now_

## Why this matters

GDPR Art. 28(3) requires a written agreement with every processor
specifying duration, nature, type of personal data, etc. The vendors'
public DPAs cover all of those; clicking "Accept" or sending a signed PDF
satisfies the requirement. Skipping it leaves Square One exposed in the
event of a vendor incident or a DPA audit by the Autoriteit
Persoonsgegevens.
