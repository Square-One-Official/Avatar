# Lifecycle-campagnes (E17.7) — seed + dispatch — GATED

Welkom → tips → launch, gedefinieerd in `admin/src/lib/lifecycleCampaigns.ts`
(getypeerd, getypecheckt). Niet-destructief: dit maakt `messages`-records; raakt
Announcements niet. Live seed/dispatch tegen DB + Resend = **THIERRY-GATED**.

## Set (lifecycleCampaign)
| Stap | sendAfterDays | cohort | kanaal | CTA |
|---|---|---|---|---|
| Welcome | 0 (window 1d) | all | both | aaavatar://import |
| Tips | 2 (window 2d) | all | both | aaavatar://effects |
| Launch (Pro) | 7 (window 7d) | freeUsers | both | aaavatar://paywall |

`toMessageDraft(step, now)` mapt een stap → Payload `messages`-create-payload met een
`targeting.signupAfter/Before`-venster, zodat de bestaande `/v1/messages`-feed (in-app) én de
sendNewsletter-dispatch (e-mail, `collection:messages`) het zonder extra logica oppikken.

## Draaien (door Thierry)
**Optie A — dagelijkse cron (aanbevolen).** Eén cron die elke dag per stap `toMessageDraft`
aanroept en het record upsert (idempotent op de datum-slug), daarna in-app vanzelf zichtbaar +
e-mail via sendNewsletter (`collection:messages`):
1. Voeg een Vercel-cron toe (admin `vercel.json` crons, bv. `0 9 * * *`) → een route die over
   `lifecycleCampaign` itereert, `payload.create({ collection: "messages", data: toMessageDraft(step) })`
   doet (skip als de datum-slug al bestaat), en voor channel email/both de send-endpoint triggert.
2. Vereist: E17.1-migratie (messages-tabel), E17.6-env (OPTIN/RESEND) + double-opt-in-besluit.

**Optie B — handmatige seed.** Een eenmalig script dat de drie records aanmaakt; daarna handmatig
"Send" per record in de Payload-admin.

## Open punt
- Signup-datum-targeting vergt dat de cohort-resolutie het signup-window respecteert — zie de
  view-uitbreiding (`created_at`) genoemd in `NIEUWSBRIEF-2.0.md` (gated follow-up). Tot dan
  werkt de in-app-feed (die filtert op public.users.created_at, E17.2) wél op het window; de
  e-mail-dispatch valt terug op het hele cohort.
