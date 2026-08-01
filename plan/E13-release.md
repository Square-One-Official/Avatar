# E13 — Release-voorbereiding

Team: **INFRA**

Laatste epic (13.0 uitgezonderd: doorlopende deploy-port, kan eerder).

## 13.0 — Backend-port v2-main → main (productie-deploy)
- status: done
- owner: INFRA
- blockedBy: —
- DoD: backend-typecheck groen op main; v2-main-kant ongewijzigd
- Context: Vercel (avatars-api, rootDirectory=backend) deployt `main`, niet v2-main. (Story toegevoegd op besluit Thierry 2026-06-12.)

Backend-wijzigingen die op v2-main landen naar `main` porten zodat ze op productie komen.
Wachten inmiddels: het recovery-endpoint `/v1/auth/send-recovery-email` (E01.7 — staat als
niet-gecommit v1-werk in de hoofd-checkout) én MODEL_REGISTRY/`model_override` (E01.10).
Tot een port gedraaid is testen agents in-app tegen een Vercel-preview-deploy van de branch
(genoteerd in E09.1 en E15.5).

**Result:** Port gedraaid 2026-06-12: branch v1/backend-port-2026-06-12 met send-recovery-email (E01.7, stond sinds 19 mei ongecommit) + de zeven E01.10-backendbestanden byte-identiek aan v2-main (diff-geverifieerd), ff-merge naar main (b27cdd5..3bc2a76) en gepusht → Vercel-productie-deploy; tsc-typecheck + models-smoke groen op main; productie-smoke OK (/v1/auth/send-recovery-email: 400 invalid_email waar eerst 404; /v1/colorize zonder auth: 401). Bewust niet mee: backend/sql/012 (device_grants account_link) — hoort bij account-link-werk dat nergens in tracked code bestaat, geen dependency van het endpoint; blijft als los punt in de hoofd-checkout. v2-main-kant ongewijzigd.

## 13.1 — Apart updatekanaal
- status: in_progress
- owner: INFRA (2026-08-01, branch v2/e13-release)
- blockedBy: — (alle FEAT-epics zijn af)
- DoD: beide targets bouwen, tests groen

Eigen appcast voor 2.0-beta; v1-gebruikers merken niets.

**Result:** _(invullen bij done)_

## 13.2 — Migratiepad
- status: in_progress
- owner: INFRA (2026-08-01, branch v2/e13-release)
- blockedBy: — (E05.4 done)
- DoD: beide targets bouwen, tests groen

v1-library → Portrait2-store (read-only import).

**Result:** _(invullen bij done)_

## 13.3 — Go/no-go-checklist
- status: in_progress
- owner: INFRA (2026-08-01, branch v2/e13-release)
- blockedBy: 13.1, 13.2 (zelfde branch)
- DoD: beide targets bouwen, tests groen

Bakeoff-besluiten verwerkt, beide apps groen, onboarding+main flow compleet, Stripe-identiteitstest
(E01.7) geslaagd.

Checklist-items uit E01.7 (INFRA, 2026-06-12):
- [ ] E2E mismatch-pad testen tegen productie. (Deploy-helft is klaar: /v1/auth/send-recovery-email
      staat sinds de E13.0-port van 2026-06-12 op productie.)

**Result:** _(invullen bij done)_

## 13.4 — Backend-port ronde 2 (v2-main → main) — KLAARGEZET
- status: done (productie-deploy 2026-06-14) — DB-migraties blijven wacht-op-Thierry
- owner: FEAT (AI-agent, marathon — voorbereiding; uitvoering door Thierry)
- blockedBy: — (klaar; alleen de gated uitvoering rest)
- DoD: de nieuwe cloud-routes draaien op productie; prod-smoke groen
- Context: vervolg op E13.0. De cloud-routes uit deze marathon (E09.2 prod-`/v1/stylize` +
  style/hair/clothes-intents, E10.3 `/v1/upscale`, E15.6 `generation_model`, E15.5
  `is_dev_unlimited`, E14.3 fill_body 2 cr) staan op v2-main maar nog niet op productie.

**Plan/voorbereiding (gedaan):**
1. Gecureerde port-manifest geschreven: **`backend/PORT-2026-06-14.md`** — exacte bestandenlijst,
   de val (send-recovery-email.ts niet verwijderen), DB-migratie 013 (gated), env/Replicate-checks,
   deploy-stappen + prod-smoke.
2. Verse Vercel-**preview** gedeployd vanaf v2-main (alle nieuwe routes):
   **https://avatars-r5jafqkdn-square-one-69d6814b.vercel.app**.

**WACHT-OP-THIERRY:** (a) de productie-deploy naar api.aaavatar.nl (stappen in PORT-2026-06-14.md;
push NIET autonoom gedaan) en (b) de DB-migratie 013 tegen de live database. Doe bij voorkeur
eerst de E01.15-e2e tegen de preview (kleding-acceptatiecriterium) vóór go-live.

**Result:** Productie-deploy gedaan 2026-06-14 (op expliciete go van Thierry). Gecureerde port van
`main` (3bc2a76) → `b27b31b`: alle v2-cloud-routes (stylize style/hair/clothes-intents, /v1/upscale,
generation_model, account.is_dev_unlimited, fill_body 1→2) + de E17-messaging-endpoints; `send-
recovery-email.ts` behouden. `npm run typecheck` groen; gepusht naar origin/main → Vercel-prod;
prod-smoke OK (/v1/stylize + /v1/upscale 401, /v1/messages 405, /v1/cutout + send-recovery intact).
DB-migraties 013 + 014 door Thierry in Supabase gedraaid (2026-06-14). **fill_body 1→2 credits is
bewust** en geldt nu ook voor live v1. Rest: Payload `messages`-tabellen via avatar-admin-deploy
(push:true) — apart, wacht-op-Thierry.

## 13.5 — Sparkle app-breed initialiseren + achtergrondcheck bij launch
- status: done
- team: INFRA
- blockedBy: —

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding C1).
**Wat:** `UpdateManager` (en dus `SPUUpdater.start()`) wordt uitsluitend
geconstrueerd als `@State` van `SettingsAboutPage.swift:19` — bij app-launch bestaat
er géén updater, dus de "Automatic updates"-toggle belooft iets dat alleen gebeurt
terwijl het About-scherm zichtbaar is. `checkForUpdatesInBackground()` heeft nul
call sites (dood). Elk About-bezoek maakt bovendien een **nieuwe** `SPUUpdater` aan
op dezelfde bundle — Sparkle verwacht er één per proces; een tweede `start()` kan
falen (belandt stil in `state = .error`). Voor een DMG-only app is dit het enige
update-kanaal → release-kritisch.
**Voorstel:** één app-brede `UpdateManager` (bv. `@State` in `Avatar2App`, doorgeven
via Environment); bij launch `checkForUpdatesInBackground()` aanroepen. About
consumeert dezelfde instance i.p.v. een eigen.
**DoD:** beide targets bouwen; een fresh launch triggert een achtergrond-update-check
zonder dat About geopend hoeft te worden; tests groen; Result-regel.

**Result:** Gedaan 2026-07-02 (branch v2/e13-5-sparkle). `Avatar2App` bezit nu dé
app-brede `UpdateManager` (`@State`, gebouwd in `init`) en geeft hem via
`.environment(updates)` door; `SettingsAboutPage` consumeert die via
`@Environment(UpdateManager.self)` — geen per-view `SPUUpdater` meer (één per proces,
zoals Sparkle eist). Bij launch roept een `.task` `checkForUpdatesInBackgroundAtLaunch()`
aan: eenmalig per proces (guard tegen venster-heropen), respecteert de "Automatic
updates"-toggle, en zet observeerbaar bewijs (`lastBackgroundCheckRequest`) + een
`.notice`-logbreadcrumb ("Launch background update check requested (E13.5)",
subsystem `nl.squareone.aaavatar2`). De echte `SPUUpdater` zit achter een nieuw
`UpdaterEngine`-seam (SparkleUpdaterEngine in prod, no-op in de unit-test-host zodat
`xcodebuild test` nooit een echte updater/netwerkcheck start, fake in tests). Nieuw:
`Avatar2Tests/UpdateManagerTests.swift` (6 tests: één engine-start, launch-check
precies één keer, toggle-uit → geen check, doorgeef-gedrag, canCheckForUpdates-mirror).
Geverifieerd: beide targets bouwen; Avatar2-tests, AvatarKit (89) en AvatarUI (37)
groen; fresh launch van de Debug-build logt de launch-check zonder dat About open was
(via `/usr/bin/log stream`).


## 13.6 — AuthSessionFileStorage: token-write faalt bij vergrendeld scherm [INFRA]
- status: done
- owner: INFRA (2026-07-12, branch v2/e13-13.6)
- team: INFRA
- blockedBy: —

Gevonden tijdens de E53.2-DoD (2026-07-12, ~02:10): `AuthSessionFileStorage.store`
schrijft met `[.atomic, .completeFileProtection]`; zodra het scherm vergrendeld is
(`CGSSessionScreenIsLocked`) faalt élke zulke write met EPERM ("mktemp failed …
errno 1", regel 37) — live gereproduceerd met een minimale `Data.write`:
`.atomic` slaagt, `.atomic + .completeFileProtection` faalt bij lock, en dezelfde
5 `AuthSessionStorageTests` die om 01:36/02:04 groen waren falen om 02:10 (scherm
op slot) in élke worktree, óók buiten de sandbox.
**Gevolg in productie:** een Supabase-token-refresh terwijl de Mac vergrendeld is
(app draait door) kan zijn sessie niet persisteren → verklaart mogelijk de
sessie-herstel-klachten die 921b1e7 (Pro grace-period) aan de symptoomkant dempt.
**Voorstel:** file-protection-klasse heroverwegen voor dit pad — bv. schrijf met
`.atomic` + `posixPermissions 0o600` (zoals nu al ná de write gezet wordt) en laat
`.completeFileProtection` vallen (macOS-keybag-semantiek ≠ iOS), óf vang de fout
en herkans na unlock (NSWorkspace.screensDidWakeNotification). Testflank: de 5
AuthSessionStorageTests draaien alleen betrouwbaar met ontgrendeld scherm —
documenteer dat in de test of maak de write-optie injecteerbaar.
**DoD:** beide targets bouwen; AuthSessionStorageTests groen mét en zonder
vergrendeld scherm (of expliciet gedocumenteerde lock-gate); Result-regel.
**Result:** ✅ `.completeFileProtection` uit `AuthSessionFileStorage.store` (alleen nog `.atomic` + de bestaande 0600/0700-permissies) — confidentialiteit komt al van de AES-GCM-envelop met Keychain-sleutel, de protection-class voegde niets toe en blokkeerde writes bij dichte keybag; rationale als comment op de write. ✅ Geverifieerd ónder vergrendeld scherm (`CGSSessionScreenIsLocked=true`): AuthSessionStorageTests 6/6 groen waar vóór de fix 5/6 faalden met EPERM — de lock-conditie zelf was het bewijs. ✅ build-v2.sh volledig groen (idem vergrendeld). ⚠ v1 heeft dezelfde bug (`Avatar/Services/FileAuthStorage.swift:56`) — niet aangeraakt (v1 bevroren, geen SHARED-story); apart besluit Thierry of dit een SHARED-fix waard is.
