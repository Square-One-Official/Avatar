# E17 — Messaging & CMS

Team: **INFRA/CMS + AI + DS + FEAT** (uitgevoerd in één autonome marathon-loop op directe
Thierry-opdracht; teamgrenzen tijdelijk opgeheven voor deze keten).

Doel: één verenigd **Message**-model dat zowel de in-app-berichten (post-sign-in modal / banner)
als de e-mail-nieuwsbrief voedt, met targeting (cohort, app-versie, platform), schedule, rich
body, image en CTA. Bouwt NIET-destructief voort op de bestaande Announcements-CMS
(`admin/src/collections/Announcements.ts`), het Announcement-backend (`/v1/announcements/*`,
`/v1/badges`), AvatarKit `AnnouncementService`, en de Resend-nieuwsbrief + cohort-revoke (sql 013).

Gated (hands-off): live DB-migraties en productie-deploys zijn THIERRY-GATED → reviewbare
bestanden + "wacht-op-Thierry". De `admin/`-Payload-build vergt DB/S3/secret-env → autonoom
alleen typecheck waar mogelijk; volledige build/migrate gated.

## 17.1 — [INFRA/CMS] Verenigd Message-model in Payload
- status: done (code + typecheck gemerged) — **live migratie = wacht-op-Thierry**
- owner: FEAT (AI-agent, marathon — CMS-werk op directe Thierry-opdracht)
- blockedBy: —
- DoD: admin-TS typecheckt; collectie geregistreerd; reviewbare migratie; Swift-build ongewijzigd groen.

**Plan:**
1. Nieuwe `Messages`-collectie (`admin/src/collections/Messages.ts`), superset van Announcements:
   `channel` (inApp|email|both), `targeting`-group (cohort: all/free/pro/specificEmails +
   signupBefore/signupAfter; minAppVersion; platform: macOS/all), `schedule` (frequency +
   publishedAt/expiresAt/untilDate/delayN), Lexical `body`, `image`, `primaryCta`, `badgeTargets`,
   `newsletter`-group. Audit-hooks zoals Announcements.
2. Registreren in `payload.config.ts` (Announcements blijft ernaast — niet-destructief).
3. Reviewbare migratie: `payload migrate:create` vergt DB → gated; lever
   `admin/MIGRATION-E17-messages.md` met het schema + draai-instructie.
4. Typecheck admin (`npx tsc --noEmit`); Swift-build ongewijzigd.

**Result:** Verenigde `Messages`-collectie (`admin/src/collections/Messages.ts`) toegevoegd —
superset van Announcements met expliciet `channel` (inApp|email|both), `targeting`-group (cohort
all/free/pro/specificEmails + signupAfter/signupBefore + minAppVersion + platform), `schedule`-
group (frequency + publishedAt/expiresAt/untilDate/delayN), Lexical `body`, `image`, `primaryCta`,
`badgeTargets`, `newsletter`-group (gated op kanaal email/both), audit-hooks zoals Announcements.
Geregistreerd in `payload.config.ts` (groep "Messaging") NAAST Announcements — niet-destructief, de
app/`/v1/announcements/*` draaien ongewijzigd door. `npx tsc --noEmit` in `admin/` = groen
(deps geïnstalleerd). Geen Swift-bestanden geraakt → build-v2 ongewijzigd groen. **wacht-op-Thierry:**
de Payload/drizzle-migratie tegen de live DB (reviewbaar bestand `admin/MIGRATION-E17-messages.md`
met genereer-/draai-stappen; alléén additief, geen DROP/ALTER op announcements).

Nieuwe `Messages`-collectie (superset van Announcements): `channel` (in-app | email | beide),
`targeting` (cohort, minAppVersion, platform), `schedule` (publishedAt/expiresAt + frequency),
Lexical `body`, `image`, `primaryCta`, `newsletter`-groep. Announcements blijft intact
(deprecated, app/backend draaien er nog op tot 17.2/17.3). Migratie = reviewbaar bestand, niet live.

## 17.2 — [INFRA] GET /v1/messages + nieuwsbrief-dispatch
- status: ready
- owner: —
- blockedBy: 17.1
- DoD: backend `npm run typecheck` groen; cohort-resolutie + targeting getest (unit waar mogelijk).

`GET /v1/messages` getarget op cohort (Starter/Pro, signup-datum via Supabase) + app-versie +
platform; nieuwsbrief-dispatch via Resend vanuit hetzelfde Message-record. Cohort-revoke/
unsubscribe behouden. Live tegen preview = gated.

## 17.3 — [AI] MessagingService in AvatarKit
- status: ready
- owner: —
- blockedBy: 17.2
- DoD: beide targets bouwen, tests groen.

`MessagingService` (port + verbetering van `AnnouncementService`): haalt getargete messages,
respecteert targeting/schedule, seen/dismiss lokaal (los van v1).

## 17.4 — [DS] DSMessageSheet + banner-variant
- status: ready
- owner: —
- blockedBy: —
- DoD: AvatarUI bouwt + tests groen; snapshot/preview-smoke.

`DSMessageSheet` + banner-variant in de v2-huisstijl (lime/dark, tokens uit E03): image + body +
CTA + dismiss. (AvatarUI tijdelijk toegestaan binnen deze marathon-opdracht.)

## 17.5 — [FEAT] In-app integratie Avatar2
- status: ready
- owner: —
- blockedBy: 17.3, 17.4
- DoD: beide targets bouwen, tests groen; visuele smoke.

Toon getarget bericht bij app-start / na eerste cutout; CTA naar feature/deeplink of extern;
seen-state persistent; geen layoutshift.

## 17.6 — [INFRA] Nieuwsbrief 2.0
- status: ready
- owner: —
- blockedBy: 17.1, 17.2
- DoD: admin/backend-TS typecheckt; templates renderen (unit waar mogelijk).

Double opt-in + React-Email-templates in nieuw merk; cohorten uit v2-onboarding (welkom na OTP,
Pro-only, re-engagement). Unsubscribe behouden. Live dispatch/DB = gated.

## 17.7 — [INFRA] Lifecycle-campagnes
- status: ready
- owner: —
- blockedBy: 17.6
- DoD: config + dispatch-logica typecheckt; reviewbaar.

Welkom → tips → launch-campagnes vanuit het Message-model (schedule/cohort-gestuurd). Live = gated.
