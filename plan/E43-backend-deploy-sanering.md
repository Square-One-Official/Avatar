# E43 — Backend-deploy-sanering & CMS/AI-achtergrond-herstel

Team: **INFRA**

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevindingen A1–A3, D2).
Kern: `Avatars/backend` (v1, main) én `Avatars-v2/backend` (v2) hebben allebei
`.vercel/project.json` → hetzelfde Vercel-project (`avatars-api`,
`prj_QbOJAhKjHdoG8luOBhtntXE2KKMN`). Prod (`api.aaavatar.nl`) draait momenteel een
4 dagen oude CLI-deploy vanaf de v2-werkdirectory: `/v1/app-config`,
`/v1/feature-flags`, `/v1/backgrounds`, `/v1/{hair,clothes,face}-presets` geven live
**404** (geprobed 2026-07-01). De client soft-failt overal naar hardcoded fallbacks,
dus dit was onzichtbaar. Omgekeerd mist de v1-repo `generate-background.ts` en
`banner-presets.ts` — de volgende GitHub-autodeploy vanaf v1-main wist die weer.
`generate-background.ts` + `BackendClient.generateBackground` zijn bovendien
**untracked** op schijf (vandaag herschreven naar het signed-URL-contract) — prod
draait nog de oudere iteratie, vandaar "Unexpected server response." bij élke
achtergrond-generatie terwijl er wél 2 credits worden afgeschreven.

---

## 43.1 — Eén deploy-bron voor api.aaavatar.nl
- status: in_progress
- team: INFRA
- blockedBy: —

**Wat:** twee repo's (`Avatars/backend` en `Avatars-v2/backend`) deployen naar
hetzelfde Vercel-project en clobberen elkaars `api/v1/*`-bestanden bij elke deploy.
**Voorstel:** de `api/v1`-bomen van beide repo's mergen tot één bron-van-waarheid
(voorstel: v2-repo als canoniek, de ontbrekende CMS-endpoints
`app-config.ts`/`backgrounds.ts`/`hair-presets.ts`/`clothes-presets.ts`/
`face-presets.ts`/`feature-flags.ts` uit v1 overnemen), óf de v1-main-autodeploy
loskoppelen van dit Vercel-project zodat alleen v2 nog deployt. Check ook
`api/appcast.ts`/`api/_appcast.xml` — die verschillen per repo en sturen de
Sparkle-updatefeed van **v1-gebruikers**; niet per ongeluk mee laten wisselen.
**DoD:** beide targets bouwen; alle eerder-404'ende endpoints geven op prod weer 200;
Result-regel met de gekozen aanpak (merge vs. loskoppelen) + motivatie.

**Status-notitie (2026-07-02):** merge klaar + preview groen; **wacht op prod-akkoord**
(prod-deploy + loskoppelen v1-autodeploy zijn bewust niet door de agent uitgevoerd).

**Result:** aanpak = **merge én loskoppelen**: v2-boom is canoniek gemaakt (beide
kanten van de divergentie verenigd), en het loskoppelen van de v1-GitHub-autodeploy
is uitgeschreven als prod-stap (zie hieronder) — motivatie: v1 is bevroren
(memory `project_v1_frozen`), dus de GitHub-integratie op de v1-repo is puur een
clobber-risico zonder functie; de CLI vanaf v2 blijft dan als enige deploy-kanaal.
Uitgevoerd op branch `v2/e43-deploy-sanering`:
- Uit v1 overgenomen (ontbraken in v2): `api/v1/app-config.ts`, `backgrounds.ts`,
  `hair-presets.ts`, `clothes-presets.ts`, `face-presets.ts`, `feature-flags.ts`
  én `api/v1/auth/send-recovery-email.ts` (Restore-Pro-flow van v1-gebruikers;
  alle lib-deps bestonden al in v2).
- `lib/payload.ts`: fetchers toegevoegd (fetchAppConfig, fetchActiveBackgrounds,
  fetchActiveHair/Clothes/FacePresets, fetchFeatureFlags) + `styleReferenceUrl`
  op `PayloadEffect` — bovenop v2's nieuwere basis (payloadBase-hardening,
  safeLinkUrl) zodat niets van v2 verloren ging.
- `api/v1/stylize.ts` + `lib/replicate.ts`: E33-CMS-gedrag teruggeplaatst
  (CMS-first preset-lookup voor hair/clothes/face + style-reference-image),
  gecombineerd mét v2's nieuwere soft_source/preserve_framing/dims-logging.
- Appcast expliciet vergeleken: v2-variant is byte-identiek aan de live feed
  behálve de 16 enclosure-URL's (`thierrzz/Avatar` → `Square-One-Official/Avatar`,
  de repo-transfer van 2026-07-01); versies/edSignatures/lengths identiek en de
  nieuwe org-URL geverifieerd (HTTP 200). v1-gebruikers blijven dezelfde feed zien.
- Preview-deploy `avatars-ex3niwdao-square-one-69d6814b.vercel.app`: alle 30
  `/v1/*`-endpoints + `/appcast.xml` bestaan (200/401/405/400 — géén enkele 404);
  de 6 eerder-404'ende CMS-endpoints geven 200 met valide JSON.
- `tsc --noEmit` groen; beide app-targets bouwen; AvatarKit `swift test` 62/0.

## 43.2 — sql/014 toepassen + generate-background live deployen + credit-refund
- status: in_progress
- team: INFRA
- blockedBy: 43.1 (dezelfde deploy-bron moet eerst vaststaan)

**Wat:** `backend/sql/014_generated_results_bucket.sql` (untracked) is vermoedelijk
niet toegepast op de prod-Supabase; `generate-background.ts` + `BackendClient.
generateBackground` (untracked, signed-URL-contract) staan niet live. Resultaat:
beide modellen (OpenAI/Gemini) falen met "Unexpected server response.", 2 credits per
poging afgeschreven zonder resultaat.
**Voorstel:** (1) migratie 014 toepassen en verifiëren (bucket `generated-results`
bestaat); (2) `generate-background.ts` + de Swift-decoder committen en deployen;
(3) contract-test die de Swift-decoder tegen de live endpoint-respons draait vóór
merge; (4) credit-refund via `credit_ledger` voor alle `generate_background`-charges
van de laatste 48 uur (reason-tag zodat het traceerbaar blijft).
**DoD:** een live generate-background-call (portret + banner) levert een zichtbaar
resultaat op zonder decode-fout; refund-script gedraaid en resultaat in de
Result-regel gemeld (aantal refunds, totaal credits).

**Status-notitie (2026-07-02):** voorbereiding compleet; **wacht op prod-akkoord**
(migratie 014, prod-deploy en refund zijn bewust niet door de agent uitgevoerd —
volgorde staat in de Result-regel).

**Result (voorbereiding):**
- `sql/014_generated_results_bucket.sql` geverifieerd: idempotent
  (`on conflict (id) do update`), private bucket, juiste mime-whitelist + 10 MB-cap.
  ⚠️ nummer-collision met `014_newsletter_double_optin.sql` (beide idempotent,
  beide toepassen) — gedocumenteerd in `sql/README.md`.
- Contract-test toegevoegd: `AvatarKitTests/GenerateBackgroundContractTests.swift`
  decodeert de létterlijke 200-JSON van `generate-background.ts` met exact de
  decoder-config van `BackendClient.request` (snake_case+iso8601); de oude
  inline-base64-vorm (de A2-outage) moet expliciet fálen. Daarvoor is de
  function-local `Response` gepromoveerd tot internal
  `BackendClient.GenerateBackgroundResponse`. Tests: 62/0 groen.
- Refund-script: `sql/016_refund_e43_generate_background_outage.sql` — stap 1 =
  dry-run (aantal charges / totaal credits / users), stap 2 = uitgecommentarieerd
  refund-INSERT, idempotent via `ref = charge-id` + NOT EXISTS, reason
  `refund_e43_generate_background_outage`. NIET gedraaid.
- Prod-volgorde ná akkoord: (1) migratie 014 in Supabase SQL-editor + bucket-check;
  (2) `vercel deploy --prod` vanaf de canonieke v2-bron; (3) live smoke
  (generate-background portret + banner); (4) refund: dry-run → INSERT-blok.

## 43.3 — Endpoint-inventaris-smoketest in CI (backlog)
- status: backlog
- team: INFRA
- blockedBy: 43.1

**Wat:** dit soort divergentie (A1) was 4 dagen onzichtbaar omdat niemand de
endpoint-inventaris tegen prod verifieerde.
**Voorstel:** een CI-stap (of losse cronjob) die na elke deploy alle bekende
`/v1/*`-endpoints probeert (GET/HEAD volstaat voor bestaan) en bij een onverwachte
404 een melding stuurt. Lijst met verwachte endpoints kan uit `BackendClient.swift`
worden afgeleid.
**DoD:** smoketest draait tegen een preview-deploy en faalt zichtbaar bij een
ontbrekend endpoint; Result-regel.

## 43.4 — Remote kill-switches voor Banners & generate-background (backlog)
- status: backlog
- team: INFRA
- blockedBy: —

**Wat:** `RemoteFeatureFlags` kent 5 flags (effects/hair/clothes/face/backgrounds,
fail-open bij CMS-uitval) — maar geen kill-switch voor de banners-suite of voor
`generate_background`, juist de twee jongste/gevoeligste paden.
**Voorstel:** twee flags toevoegen aan `/v1/feature-flags`
(`banners_enabled`/`background_generate_enabled`, default `true` fail-open) en de
bestaande call sites (`AppFeatureFlags.bannersEnabled`, `GenerateBackgroundSheet`)
ermee laten samenwerken zodat een server-side noodstop mogelijk is zonder
app-release.
**DoD:** flag omzetten op een preview-deploy schakelt de feature client-side
zichtbaar uit; Result-regel.

## 43.5 — Untracked werk committen
- status: done
- owner: hoofdsessie (2026-07-02)
- team: INFRA (coördineert; elk team staget zijn eigen paden)
- blockedBy: —

**Result:** volledige dirty staat van v2-main eerst gevalideerd (Avatar + Avatar2 builds groen, AvatarKit 59/0, AvatarUI 37/0) en daarna per pad gecommit in 9 logische commits `ecf00d2`…`3ce73b3` (cutout-sanering incl. beide deletes, release-URLs, E42, banners+editor, shell/DS, admin, plan, projectregistratie); `git status` toont alleen nog `.cursor/` (bewust untracked).

**Wat:** `git status` toont ±30 untracked source-files die de app wél compileert
(heel `Features/Background/`, de AI-privacy-tier-stack in `Features/Settings/`,
7 Banner-files, `backend/api/v1/generate-background.ts`, `backend/sql/014_*.sql`) plus
gestagede deletes (`CloudCutoutEngine.swift` + test) en een unstaged delete
(`HeroMorph.swift`). Eén verkeerde `git clean` en dit werk is weg.
**Voorstel:** per pad stagen en committen (nooit `git add -A` op `v2-main` — memory
`v2_main_concurrent_sessions`); de twee deletes in dezelfde beurt meenemen.
**DoD:** `git status` toont geen onverwachte untracked/uncommitted bestanden meer die
al in productie-gebruik zijn; Result-regel met de commit-hashes.
