# Go/no-go — Aaavatar 2.0 (E13.3)

Status per 2026-08-01. ✅ = geverifieerd (hoe staat erbij) · ⬜ = open, met
eigenaar. **Regel: alles wat ⬜ staat is een bewust besluit van Thierry — óf
doen, óf expliciet accepteren als launch-risico.** De agent-kant is af; wat
rest is gated (deploys, signing, live oog-/betaaltests).

## 1. Build & tests — ✅

- ✅ Beide targets bouwen, alle suites groen: `scripts/build-v2.sh` "alles
  groen" (2026-08-01, incl. de reduce-motion- en icoongrootte-guards).
  200 Avatar2-tests · 100+ AvatarKit · 55 AvatarUI.
- ✅ Verse checkout van v2-main bouwt (worktree-check gedaan bij E53.5/E53.2).
- ✅ v1 (`Avatar`-target) bouwt mee in elke DoD-run — bevroren maar niet kapot.

## 2. Flows compleet — ✅ (code) / ⬜ (laatste oogtest)

- ✅ Onboarding (E04), main shell (E05), editor (E06+), settings (E15),
  monetization (E14): alle epics `done` op het board.
- ✅ UX-audit-epic E53 volledig gesloten (53.1–53.9).
- ⬜ **Laatste visuele pass** (Thierry): Home's nieuwe tijdsecties (E53.5 —
  hero-kaart is weg), reduce-motion-oogtest (E53.4), icoongrootte-oogtest
  (E53.9), dark+light shell-smoke (E53.6). Elk staat met details in de
  story-Result.

## 3. Bakeoff-besluiten verwerkt — ✅ op één na

- ✅ E09.1 stylize → nano-banana (default in MODEL_REGISTRY).
- ✅ E41.5 upscale → Regular (google, 1 cr) / High (Topaz 3 cr, 6 MP-cap);
  backend live sinds 2026-07-12.
- ✅ E54.2 stijlreferenties → default UIT (bakeoff-verdict 2026-07-12).
- ✅ E10.2 kleding → nano-banana instruction-edit.
- ⬜ **E32.0 face-bakeoff is nooit gedraaid** — E32.1 (face-intent, code
  compleet + backend op prod) staat daarop te wachten. Besluit: bakeoff
  draaien vóór launch, óf launchen met nano-banana-baseline en de bakeoff
  daarna. De Beauty-kaarten wérken (prod heeft `face_preset`); alleen de
  modelkeuze is onbevestigd.

## 4. Update-kanaal (13.1) — ✅ code / ⬜ deploy + eerste release

- ✅ Eigen feed: Avatar2 → `api.aaavatar.nl/appcast-v2.xml`; v1 ongewijzigd op
  `/appcast.xml` (beide Info.plists geverifieerd). Eigen versielijn 2.0.0
  (build 100) los van v1's 1.2.1/18 (`xcodebuild -showBuildSettings` op beide
  targets geverifieerd).
- ✅ `release.sh` (v1) bumpt alleen nog het root-blok — kan v2 niet meer
  hernummeren; `release-v2.sh` bumpt alleen het Avatar2-blok (assert op
  precies 2 matches).
- ✅ v2-releases zijn GitHub-**prereleases** — anders kaapt een 2.0-release
  de `releases/latest`-link waar de website v1's DMG vandaan haalt.
- ⬜ **Backend-deploy** (Thierry, E13.0-route): `/appcast-v2.xml` geeft op
  prod nu 404 (endpoint bestaat alleen op v2-main). Port → main → Vercel;
  smoke: `curl -s https://api.aaavatar.nl/appcast-v2.xml` → lege channel-XML.
- ⬜ **Eerste beta-release** (Thierry: signing/notarisatie/Sparkle-key):
  `./scripts/release-v2.sh 2.0.0 101`, daarna appcast-v2-commit + backend-
  deploy, en een update-e2e (oude beta-build → nieuwe via Sparkle).

## 5. Migratiepad (13.2) — ✅ code / ⬜ echte-data-test

- ✅ v1-back-up (.zip) → Portrait2: `V1LibraryArchive` (AvatarKit, 5 tests op
  het echte zip-formaat incl. schema-weigering) + `V1LibraryImporter`
  (6 tests: idempotent, overschrijft nooit v2-bewerkingen, "Aaavatar 1"-map,
  echte v1-datums). Instap: Settings → Preferences → "Import backup…".
- ✅ Read-only per constructie: v2 leest alleen het gekozen zip-bestand;
  v1's store is onbereikbaar (andere sandbox) en wordt nooit aangeraakt.
- ⬜ **E2E met een échte v1-bibliotheek** (Thierry): exporteer in v1
  (Settings → bibliotheek-back-up), importeer in v2, controleer aantallen +
  namen + dat de "Aaavatar 1"-map netjes in Earlier landt.

## 6. Stripe-identiteit (E01.7) — ⬜ Thierry

- ✅ Deploy-helft: `/v1/auth/send-recovery-email` staat op prod (E13.0).
- ⬜ **E2E mismatch-pad tegen productie**: log in met een e-mail die niét bij
  de Stripe-customer hoort → recovery-mail-pad → verifieer dat de koppeling
  (Supabase user-id ↔ Stripe) klopt. Vergt echte Stripe-testdata; bewust
  nooit autonoom gedaan.
- ⬜ Stripe-webhook delivery-log nalopen (CTO-B8) — kort: dashboard →
  webhooks → recente deliveries zonder failures.

## 7. Backend & productie-surface — ✅ op de gated deploys na

- ✅ Prod-smoke (2026-08-01): 8 CMS/preset-endpoints → 200; 6 betaalde
  POST-routes zonder auth → 401; `/appcast.xml` → 200.
- ⬜ **Custom effects live** (E09.3, Thierry): `sql/015` op prod-Supabase +
  backend-deploy — tot dan geeft de Create-knop een serverfout (app soft-failt).
- ⬜ **Nieuwsbrief double-opt-in** (E17.6, DECISIONS-PENDING): besluit vóór de
  eerste marketing-dispatch, niet blokkerend voor de app-launch zelf.

## 8. Feature-flags & vangnetten — ✅

- ✅ `bannersEnabled` default UIT (besluit 2026-07-12) — alleen de matched-
  background banner-export in Social Preview is live.
- ✅ Sparkle app-breed + launch-achtergrondcheck (13.5); token-writes bij
  vergrendeld scherm gefixt (13.6); E46-bevestigingen op destructieve acties;
  E44-fouttoasts; E47-testfundament.

## 9. Assets — ⬜ Thierry (bewust, ASSETS.md)

- ⬜ De 5 geregistreerde placeholders (splash, memoji-set, background-prints,
  effect-previews, canvas-toolbar-design) — één batch, expliciet besluit of
  de beta met placeholders mag.

## Kort: wat moet er minimaal gebeuren vóór "go"

1. Backend-port + deploy (appcast-v2 · custom-effects/sql-015) — één ronde.
2. `release-v2.sh 2.0.0 101` + Sparkle-update-e2e.
3. v1→v2 migratie-e2e met echte bibliotheek.
4. Stripe-mismatch-e2e + webhook-log.
5. Visuele passes (Home-secties voorop) + besluit E32.0 (bakeoff vóór of ná).
6. Besluit assets: batch aanleveren of beta-met-placeholders.
