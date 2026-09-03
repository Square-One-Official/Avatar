# Nieuwsbrief 2.0 (E17.6) — overzicht + gated stappen

Niet-destructief bovenop de bestaande nieuwsbrief (Announcements + Resend +
`newsletter_cohorts`-view + `newsletter-unsubscribes`). Alles wat de live DB of
echte e-mail-verzending raakt is **THIERRY-GATED**.

## Wat is gebouwd (code, getypecheckt, gemerged)
- **v2-merk-template** `admin/src/emails/MessageEmail.tsx` — donker + lime CTA, zelfde
  props/footer als AnnouncementEmail (die blijft voor de oude flow).
- **Dispatch vanuit het Message-model** — `admin/src/endpoints/sendNewsletter.ts` accepteert nu
  `collection: "messages"` (default "announcements"): gate op `channel` email/both, recipients uit
  `targeting.cohort`/`targeting.audienceEmails` (zelfde keys → bestaande `resolveRecipients`),
  MessageEmail-template, `newsletter.sentAt`-stempel. Announcement-pad ongewijzigd.
- **Double-opt-in mechaniek** — `admin/src/lib/optin-token.ts` (signer + `confirmUrlFor`) +
  `backend/lib/optin-token.ts` (verifier, 14d TTL) + `backend/api/v1/newsletter/confirm.ts`
  (GET ?token → upsert `newsletter_optins.confirmed_at` → bevestigingspagina).

## Gated (door Thierry uit te voeren)
1. **DB-migratie** `backend/sql/014_newsletter_double_optin.sql` — maakt `public.newsletter_optins`.
   Draai handmatig na review (additief; geen DROP/ALTER op bestaande tabellen).
2. **Env** op beide Vercel-projecten: `OPTIN_SIGNING_SECRET` (of hergebruik
   `UNSUBSCRIBE_SIGNING_SECRET`), `OPTIN_BASE_URL` (default api.aaavatar.nl).
3. **Echte verzending** via de admin "Send"-knop met `collection:messages` — Resend-blast naar
   echte ontvangers; doe eerst een testMode-send.

## Cohorten uit v2-onboarding (welkom / Pro-only / re-engagement)
- **Welkom na OTP**: roep `confirmUrlFor(email)` aan in de OTP-welkomstmail (v2-onboarding,
  backend) → gebruiker bevestigt → `newsletter_optins.confirmed_at`. Daarna valt hij in cohort
  `all`/`freeUsers` van de `newsletter_cohorts`-view.
- **Pro-only**: Message met `targeting.cohort = proUsers`.
- **Re-engagement**: `targeting.signupBefore` (oude accounts). Let op: de huidige
  `newsletter_cohorts`-view levert `email`+`tier`, **geen** `created_at` → signup-datum-filtering
  vergt een view-uitbreiding (kolom `created_at`) + filter in `resolveRecipients`. Klein, gated
  follow-up; nu nog niet bedraad zodat de live view/flow ongemoeid blijft.

## Double-opt-in filtering (bewuste keuze, niet retroactief)
`newsletter_optins` is een **additief** opt-in-grootboek. De dispatch filtert er nu NIET op,
zodat bestaande account-houders (die al via accountregistratie opt-in gaven) niet plots
uitgesloten worden. Voor puur-marketing-cohorten kan de dispatch optioneel op
`confirmed_at IS NOT NULL` filteren — ontgrendel dat samen met de view-grant in 014. Dit besluit
staat ook in plan/DECISIONS-PENDING.md voor expliciete bevestiging.
