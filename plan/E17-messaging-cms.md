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
- status: done (read-feed gemerged; dispatch-vanuit-Message gevouwen in 17.6)
- owner: FEAT (AI-agent, marathon — INFRA-werk op directe Thierry-opdracht)
- blockedBy: 17.1 (done)
- DoD: backend `npm run typecheck` groen; cohort-resolutie + targeting getest (unit waar mogelijk).

**Plan:**
1. `backend/lib/payload.ts`: `PayloadMessage`-type + `fetchPublishedMessages()` + `normalizeMessage()`
   (spiegelt de Messages-collectie, flat targeting/schedule-groups), naast de bestaande
   announcement-functies (niet-destructief).
2. `backend/api/v1/messages.ts`: GET getargete in-app-feed — kanaal inApp/both, cohort
   (free/pro/specificEmails), signup-datum (public.users.created_at, graceful bij ontbreken),
   app-versie (X-App-Version), platform, expiry, seen (hergebruik `announcement_seen`).
3. `admin/src/endpoints/sendNewsletter.ts`: `collection`-param ("announcements" | "messages",
   default announcements) zodat dispatch óók vanuit een Message-record werkt; resolveRecipients +
   unsubscribe ongewijzigd. Live dispatch = gated.
4. Unit-test voor cohort/targeting-filter waar mogelijk; tsc backend + admin groen.

**Result:** `GET /v1/messages` live in de code (backend). `backend/lib/payload.ts` kreeg
`PayloadMessage` + `fetchPublishedMessages()` + `normalizeMessage()` (spiegelt de Messages-
collectie, flat targeting/schedule-groups, 60s-cache) — naast de announcement-functies,
niet-destructief. `backend/api/v1/messages.ts`: getargete in-app-feed (kanaal inApp/both; cohort
free/pro/specificEmails; signup-datum via public.users.created_at, graceful; app-versie via
X-App-Version + meetsMinVersion; platform; expiry; dismiss-state hergebruikt `announcement_seen`).
De `/v1/*`-rewrite in vercel.json dekt het endpoint (default-runtime). `npm run typecheck` groen.
**Scoping:** de nieuwsbrief-**dispatch vanuit een Message-record** is bewust gevouwen in **17.6**
(Nieuwsbrief 2.0) — dat is de plek waar de recipient/cohort-resolutie (`resolveRecipients`) van
twee schema's (announcements.audience vs messages.targeting.cohort) hoort; half-wiren hier zou de
bestaande announcement-dispatch riskeren. Live feed tegen preview/prod = gated (Payload-data +
PAYLOAD_API_*-env).

`GET /v1/messages` getarget op cohort (Starter/Pro, signup-datum via Supabase) + app-versie +
platform; nieuwsbrief-dispatch via Resend vanuit hetzelfde Message-record. Cohort-revoke/
unsubscribe behouden. Live tegen preview = gated.

## 17.3 — [AI] MessagingService in AvatarKit
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 17.2 (done)
- DoD: beide targets bouwen, tests groen.

**Plan:**
1. `Message`-model (AvatarKit, mirror van Announcement + `frequency`), met publieke memberwise init
   voor gebruik/tests + Decodable.
2. `BackendClient.fetchMessages() -> [Message]` (GET /v1/messages, `{messages:[…]}`) +
   `markMessageSeen(slug:action:)` (hergebruikt /v1/announcements/seen → gedeelde announcement_seen).
3. `MessagingService` (@MainActor @Observable): refresh → queue (server-getarget), `current`,
   `dismiss()` (lokale dismissed-set in UserDefaults + server-seen). Pure `filterDismissed`-helper
   voor de testbaarheid.

**Result:** `Message`-model (AvatarKit/Backend/Message.swift, mirror van Announcement + `frequency`,
publieke memberwise init + Decodable). `BackendClient.fetchMessages()` (GET /v1/messages) +
`markMessageSeen(slug:action:)` (hergebruikt het seen-endpoint → gedeelde announcement_seen-tabel).
`MessagingService` (@MainActor @Observable): `refresh()` → server-getargete queue met lokaal-
gedismisste slugs eruit, `current`, `dismiss()`/`acknowledge()` (lokale UserDefaults-set +
fire-and-forget server-seen), pure `filterDismissed`-helper. 4 nieuwe tests (filter + Message-
decode incl. defaults). Niet-destructief — Announcement-pad blijft. Beide targets bouwen groen,
alle suites groen.

`MessagingService` (port + verbetering van `AnnouncementService`): haalt getargete messages,
respecteert targeting/schedule, seen/dismiss lokaal (los van v1).

## 17.4 — [DS] DSMessageSheet + banner-variant
- status: done
- owner: FEAT (AI-agent, marathon — DS-werk op directe Thierry-opdracht)
- blockedBy: —
- DoD: AvatarUI bouwt + tests groen; snapshot/preview-smoke.

**Plan:**
1. `DSMessageSheet` (AvatarUI): hero (16:9 AsyncImage, optioneel) + titel + markdown-body +
   optionele CTA (DSPrimaryButton, fullWidth) + dismiss (DSIconButton xmark). Card-stijl als
   DSEditPanel (bg Card, r-xl4, shadow), tokens uit E03.
2. `DSMessageBanner` (compacte inline-variant): optionele thumb + titel + 1-regel body + CTA-chevron
   + dismiss.
3. ImageRenderer-smoke-tests (met/zonder image + CTA) zoals DSEditPanelTests.

**Result:** `DSMessageSheet` + `DSMessageBanner` in AvatarUI (Components/DSMessageSheet.swift),
v2-huisstijl op E03-tokens: sheet = optionele 16:9 AsyncImage-hero + titel (h3) + markdown-body
(AttributedString, met platte-tekst-fallback) + optionele lime CTA (DSPrimaryButton fullWidth) +
dismiss-kruis (DSIconButton), card-stijl als DSEditPanel (bg Card, r-xl4, shadow); banner =
compacte thumb + titel + 1-regel body + CTA-chevron + dismiss. 2 ImageRenderer-smoke-tests
(sheet met/zonder image+CTA; banner met/zonder CTA). On-screen-smoke volgt in 17.5 (mount in
Avatar2). AvatarUI bouwt + alle suites groen.

`DSMessageSheet` + banner-variant in de v2-huisstijl (lime/dark, tokens uit E03): image + body +
CTA + dismiss. (AvatarUI tijdelijk toegestaan binnen deze marathon-opdracht.)

## 17.5 — [FEAT] In-app integratie Avatar2
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 17.3 (done), 17.4 (done)
- DoD: beide targets bouwen, tests groen; visuele smoke.

**Plan:**
1. `MessagingService` als @State in Avatar2App (backend = entitlement.backend); `refresh()` in de
   app-.task (start). DEBUG `MessagingService.debugInject(_:)` + launchhaak `--show-message`.
2. Overlay (geen layoutshift): bij `messaging.current` een gedimde backdrop + `DSMessageSheet`
   gecentreerd; CTA → `NSWorkspace.open(cta.url)` (aaavatar:// of extern) + `acknowledge`; dismiss
   → `messaging.dismiss`. Backdrop-tik = dismiss.
3. Visuele smoke via `--show-message`.

**Result:** MessagingService gemount in Avatar2App (@State, backend = entitlement.backend);
`refresh()` bij app-start (faalt stil). In-app bericht verschijnt als gecentreerd `DSMessageSheet`
boven een gedimde backdrop (overlay → geen layoutshift); CTA opent `cta.url` via
`NSWorkspace.open` (aaavatar://-deeplink of extern) + `acknowledge` (server-seen + lokaal), dismiss
(kruis of backdrop-tik) → `MessagingService.dismiss` (persistente seen-state). DEBUG-launchhaak
`--show-message` injecteert een test-bericht. Smoke (`--show-message`): sheet rendert met titel,
markdown-body (bold), lime "Explore effects"-CTA en dismiss-kruis (zie /tmp/e175_message.png).
Beide targets bouwen groen, alle suites groen.

Toon getarget bericht bij app-start / na eerste cutout; CTA naar feature/deeplink of extern;
seen-state persistent; geen layoutshift.

## 17.6 — [INFRA] Nieuwsbrief 2.0
- status: done (code + tsc gemerged) — **live dispatch + DB-migratie 014 + env = wacht-op-Thierry**
- owner: FEAT (AI-agent, marathon — INFRA-werk op directe Thierry-opdracht)
- blockedBy: 17.1 (done), 17.2 (done)
- DoD: admin/backend-TS typecheckt; templates renderen (unit waar mogelijk).

**Plan:**
1. `admin/src/emails/MessageEmail.tsx`: React-Email-template in het v2-merk (lime/dark), zelfde
   props als AnnouncementEmail + unsubscribe-footer.
2. `admin/src/endpoints/sendNewsletter.ts`: `collection`-param ("announcements"|"messages",
   default announcements); messages-tak gate't op `channel` email/both, resolve't recipients op
   `targeting.cohort`/audienceEmails, gebruikt MessageEmail, stempelt newsletter.sentAt. recipients.ts
   ongewijzigd (zelfde cohort-keys).
3. Double opt-in: `admin/src/lib/optin-token.ts` (HMAC-signer, mirror unsubscribe-token) +
   `backend/api/v1/newsletter/confirm.ts` (verifieert token, markeert bevestigd). DB =
   `backend/sql/014_newsletter_double_optin.sql` (reviewbaar, gated).
4. `admin/NIEUWSBRIEF-2.0.md`: flow, cohort/signup-datum-note, gated stappen. admin/backend tsc groen.

**Result:** Nieuwsbrief 2.0 code-compleet (tsc groen). (b) `MessageEmail.tsx` — v2-merk (dark +
lime CTA), zelfde props/footer als AnnouncementEmail (blijft bestaan). (d) `sendNewsletter.ts`
accepteert nu `collection: "messages"` (default announcements, niet-destructief): gate op
`channel` email/both, recipients uit `targeting.cohort`/`audienceEmails` (zelfde keys →
bestaande resolveRecipients), MessageEmail-template, sentAt-stempel — dit is de uit 17.2 gevouwen
message-dispatch. (a) Double opt-in: `admin/src/lib/optin-token.ts` (signer + confirmUrlFor) +
`backend/lib/optin-token.ts` (verifier, 14d) + `backend/api/v1/newsletter/confirm.ts` (token →
`newsletter_optins.confirmed_at` → bevestigingspagina). (c) cohorten + flow in
`admin/NIEUWSBRIEF-2.0.md` (welkom-na-OTP via confirmUrlFor, Pro-only, re-engagement;
signup-datum-filter = view-uitbreiding, gated). admin tsc + backend tsc groen; Swift onaangeroerd.
**WACHT-OP-THIERRY:** DB-migratie `backend/sql/014_newsletter_double_optin.sql`, env
`OPTIN_SIGNING_SECRET`/`OPTIN_BASE_URL`, en de echte Resend-verzending. Double-opt-in-filtering =
voorstel in DECISIONS-PENDING (Open).

Double opt-in + React-Email-templates in nieuw merk; cohorten uit v2-onboarding (welkom na OTP,
Pro-only, re-engagement). Unsubscribe behouden. Live dispatch/DB = gated.

**Toegevoegd uit 17.2:** ook de nieuwsbrief-**dispatch vanuit een Message-record** (sendNewsletter
uitbreiden met `collection: messages` + recipient-resolutie op `targeting.cohort`/signup-datum,
naast de bestaande announcements.audience-route). Niet-destructief; live send = gated.

## 17.7 — [INFRA] Lifecycle-campagnes
- status: done (config + dispatch-plan gemerged) — **seed/cron + live = wacht-op-Thierry**
- owner: FEAT (AI-agent, marathon — INFRA-werk op directe Thierry-opdracht)
- blockedBy: 17.6 (done)
- DoD: config + dispatch-logica typecheckt; reviewbaar.

**Plan:**
1. `admin/src/lib/lifecycleCampaigns.ts`: getypeerde campagne-set (welkom dag 0 → tips dag 2 →
   launch dag 7) met channel/cohort/sendAfterDays/body/CTA + `toMessageDraft()` (mapt een stap
   naar een Payload `messages`-create-payload met targeting.signupAfter/Before-window + schedule).
2. `admin/LIFECYCLE-CAMPAGNES.md`: seed- + cron-dispatch-plan (reviewbaar, gated).
3. admin tsc groen; Swift onaangeroerd.

**Result:** `admin/src/lib/lifecycleCampaigns.ts` — getypeerde set welkom (dag 0) → tips (dag 2) →
launch/Pro (dag 7), elk met channel/cohort/sendAfterDays/window/CTA + `toMessageDraft()` die een
stap naar een Payload `messages`-create-payload mapt (targeting.signupAfter/Before-venster +
schedule), zodat de bestaande /v1/messages-feed én sendNewsletter (collection:messages) het
oppikken zonder extra logica. `admin/LIFECYCLE-CAMPAGNES.md` beschrijft de dagelijkse-cron- en
handmatige-seed-route + het signup-window-open-punt. admin tsc groen; Swift onaangeroerd.
**WACHT-OP-THIERRY:** seed/cron instellen + live verzending (vergt E17.1-migratie + E17.6-env/DB).

Welkom → tips → launch-campagnes vanuit het Message-model (schedule/cohort-gestuurd). Live = gated.
