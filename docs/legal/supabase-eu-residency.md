# Supabase EU residency — contract confirmation

_Audit MEDIUM #30. Goal: get a written confirmation from Supabase that
the Aaavatar project (`<ref>.supabase.co`) is pinned to an EU region
and that personal data does not leave the EU under normal operations.
Owner: Thierry._

The Supabase project was provisioned in `eu-central-1` (Frankfurt) and
the dashboard confirms that's where the Postgres + Storage live. That's
enough for operational purposes — but for an Art. 28 GDPR DPA the
controller (Square One) needs a contractual guarantee, not just a
dashboard setting.

## Status

| Item | Status | When |
|---|---|---|
| Supabase DPA accepted in dashboard | ☐ todo | — |
| Counter-signed DPA on file | ☐ todo | — |
| Written EU-residency commitment | ☐ todo | — |
| Subprocessor list incorporated by reference | ☐ todo | — |

## Asking Supabase

Open a support ticket from the Supabase dashboard with the template
below (or paste into a fresh email to support@supabase.com referencing
the project ref).

> Subject: GDPR Art. 28 — written confirmation of EU data residency
>
> Hi Supabase team,
>
> I'm the controller for project `<ref>.supabase.co` (the "Aaavatar"
> project), serving EU/EEA end users out of the Netherlands.
>
> For our Art. 28 GDPR documentation I need a written confirmation of:
>
> 1. That the Postgres database, Auth user records, and Storage buckets
>    associated with this project are hosted in your `eu-central-1`
>    (Frankfurt) region, and that the data is processed and stored
>    exclusively in EU / EEA regions under normal operations.
> 2. The conditions under which data may transit outside the EU/EEA
>    (support access, backups, etc.) and the safeguards in place
>    (Standard Contractual Clauses, encryption in transit, role
>    restrictions).
> 3. A counter-signed copy of your DPA at <https://supabase.com/legal/dpa>
>    (if you can email a signed PDF; otherwise the click-through
>    acceptance receipt is fine for our records).
> 4. A current Subprocessor List so we can incorporate it by reference
>    in our own privacy notice.
>
> Customer name on file: Square One (Netherlands)
> Billing contact: thierry@squareone.nl
> Project ref: `<ref>.supabase.co`
>
> Thanks,
> Thierry

## File the response under

- `docs/legal/dpa/supabase-residency-<YYYYMMDD>.pdf` (gitignored — see
  `docs/legal/dpa-tracking.md`).
- Update [`dpa-tracking.md`](dpa-tracking.md) row for Supabase: change ☐
  to ☑ and fill the Signed-copy column.
- Update the **Status** table at the top of this file with the date.

## Out of scope (separate vendor letters)

- **Replicate**: covered by [`dpia-image-processing.md`](dpia-image-processing.md)
  — image transits to US under SCCs, retention is short. If the DPA
  audit demands a written counter-signed copy, file the same flow
  against `legal@replicate.com`.
- **Stripe / Resend / Upstash / Vercel**: their public DPAs are
  click-through; saving the receipt PDF is sufficient. Track in
  `dpa-tracking.md`.
