# Migratie E17.1 — `messages`-collectie (Payload/Postgres) — GATED

**Status: KLAAR OM TE DRAAIEN — THIERRY-GATED.** Niet autonoom uitgevoerd: een
Payload/drizzle-migratie tegen de live database vergt DB-toegang en is een
door Thierry te bevestigen actie. Dit bestand is de reviewbare voorbereiding.

## Wat verandert
Nieuwe collectie `Messages` (slug `messages`) toegevoegd aan
`admin/src/payload.config.ts`, naast (niet in plaats van) `Announcements`.
NIET-destructief: de bestaande `announcements`-tabel + alle gerelateerde
tabellen blijven ongemoeid; de macOS-app en `/v1/announcements/*` draaien er
ongewijzigd op tot E17.2/E17.3.

De collectie voegt deze tabellen toe (Payload/drizzle leidt ze af uit
`Messages.ts`):
- `messages` (hoofdtabel: title, slug [unique], channel, body [jsonb/lexical],
  image [media-FK], primaryCta_label/url, targeting_cohort, targeting_signupAfter,
  targeting_signupBefore, targeting_minAppVersion, targeting_platform,
  schedule_frequency, schedule_untilDate, schedule_delayN, schedule_publishedAt,
  schedule_expiresAt, newsletter_subject, newsletter_fromName,
  newsletter_customBody [jsonb], newsletter_sentAt, createdAt, updatedAt)
- `messages_targeting_audience_emails` (array: email)
- `messages_badge_targets` (array: componentId [badge-components-FK], durationDays)
- `messages_rels` (Payload relationship-join voor image/badge-components)

(Exacte kolomnamen/typen genereert Payload zelf; bovenstaande is de
verwachte vorm ter review.)

## Genereren + draaien (door Thierry, met DB-toegang)
```bash
cd admin
# Env nodig: PAYLOAD_SECRET, PAYLOAD_DATABASE_URL (of DATABASE_URL /
# POSTGRES_URL_NON_POOLING), S3_* — zoals in payload.config.ts.
npx payload migrate:create messages_collection   # schrijft admin/src/migrations/<ts>_messages_collection.ts
# Review de gegenereerde migratie (alleen CREATE TABLE messages*, geen DROP/ALTER op announcements*).
npx payload migrate                               # past toe; idempotent
```
Op Vercel draait `vercel-build` (`payload generate:importmap && payload migrate
&& next build`) de migratie automatisch bij de volgende admin-deploy — controleer
dus dat de gegenereerde migratie in de repo staat en alléén additief is vóór die
deploy.

## Verificatie
- `npx tsc --noEmit` in `admin/` = groen (geverifieerd in deze story).
- Na migrate: Payload-admin toont een "Messages"-collectie (groep "Messaging")
  naast "Announcements"; bestaande announcements ongewijzigd.

## Niet in deze story (volgende E17-stories)
- `/v1/messages` + cohort-resolutie + Resend-dispatch (E17.2).
- Data-overzet announcements → messages (optioneel; beide bestaan naast elkaar,
  geen verplichte datamigratie).
