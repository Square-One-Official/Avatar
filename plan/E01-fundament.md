# E01 — Fundament

Team: **INFRA**

Lege Aaavatar 2.0-app die naast de oude draait.

## 1.1 — Scaffold Avatar2-target
- status: done
- owner: INFRA
- blockedBy: —
- DoD: beide targets bouwen, tests groen

Nieuw app-target `Avatar2` in het bestaande Xcode-project (bundle-id nl.squareone.aaavatar2, eigen
icon-placeholder). Oude target onaangeroerd. DoD: beide apps bouwen en starten.

**Result:** Avatar2-target (nl.squareone.aaavatar2, eigen icon-placeholder) toegevoegd via project.yml + xcodegen; beide targets bouwen Debug groen; Aaavatar 2.app start en toont placeholder.

## 1.2 — AvatarKit package
- status: done
- owner: INFRA
- blockedBy: 1.1
- DoD: beide targets bouwen, tests groen

Swift package met skelet: `CutoutEngine`-protocol + `PipelineRouter`-stub. Avatar2 linkt ertegen.

**Result:** AvatarKit lokale SwiftPM-package (CutoutEngine-protocol, CutoutEngineKind, PipelineRouter-stub in Sources/AvatarKit/Engines/); Avatar2 linkt en gebruikt het; package + beide targets bouwen groen.

## 1.3 — AvatarUI package
- status: done
- owner: INFRA
- blockedBy: 1.1
- DoD: beide targets bouwen, tests groen

Leeg Swift package-skelet voor het design system. Avatar2 linkt ertegen.

**Result:** AvatarUI lokale SwiftPM-package (leeg skelet met versie-anker); Avatar2 linkt ertegen; package + beide targets bouwen groen.

## 1.4 — Testtargets + buildscript
- status: done
- owner: INFRA
- blockedBy: 1.2, 1.3
- DoD: beide targets bouwen, tests groen

Testtargets voor AvatarKit en AvatarUI, één smoke-test, xcodebuild-script dat beide apps + tests
draait.

**Result:** XCTest-targets voor beide packages (5 router-tests + smoke-test) en scripts/build-v2.sh (xcodegen + beide targets + beide testsuites); alles groen.

## 1.5 — SHARED: BackendClient naar AvatarKit
- status: done
- owner: INFRA
- blockedBy: 1.2
- DoD: beide targets bouwen, tests groen

BackendClient (auth/entitlement/cloud-calls) verplaatsen naar AvatarKit; oude app consumeert hem
vandaaruit. Enige story die Avatar/ mag raken.

**Result:** BackendClient + TLSPinning + DeviceFingerprint + entitlement-wire-types + Announcement-modellen naar AvatarKit/Backend/ (public API, AuthManager gekoppeld via nieuw AccessTokenProviding-protocol); Avatar, Avatar-MAS en Avatar2 bouwen groen, tests groen, v1 start-smoke OK.

## 1.6 — Auth 2.0: e-mail + code
- status: done
- owner: INFRA
- blockedBy: 1.2
- DoD: beide targets bouwen, tests groen

Nieuwe AuthService in AvatarKit op Supabase signInWithOTP/verifyOTP. Geen OAuth/PKCE/deep-link voor
auth. Backend auth.ts ongewijzigd. Google-infra blijft bestaan maar krijgt geen UI in 2.0.

**Result:** AuthService (@Observable, requestCode/verifyCode/signOut via Supabase signInWithOTP+verifyOTP, conformeert aan AccessTokenProviding) in AvatarKit/Auth/ met AES-GCM-versleutelde sessie-opslag (eigen Keychain-service nl.squareone.aaavatar2, zelfde ontwerp als v1 audit-fix HIGH #7); supabase-swift 2.x als package-dependency; beide targets bouwen groen, 31 AvatarKit-tests groen (6 nieuwe storage-tests).

## 1.7 — Stripe/identiteit-verificatie OTP-switch
- status: done
- owner: INFRA
- blockedBy: 1.6
- DoD: beide targets bouwen, tests groen

Test: OTP-login op e-mail van bestaande Google-user → zelfde Supabase-user (Pro behouden). Test
mismatch-pad → RecoverPro (send-recovery-email). URL-scheme behouden voor stripe-return/cancel.
Google-infra NIET slopen.

Notities (INFRA, bij oplevering):
- Identiteitstest GESLAAGD op productie: OTP-verify (publishable key, type email — exact het
  AuthService-pad) op thierryemmery@gmail.com → sessie voor user 1ecc47b2… (provider google,
  bestaande Pro-user); /v1/account met dat token → tier pro, status active. Idem voor
  thierry@squareone.nl → user 4499ec26… (dev-unlimited pro). Geen nieuw account aangemaakt;
  Google-infra onaangeroerd.
- Productie-bug gevonden én deels opgelost: Supabase custom SMTP stond op poort 462 (typo,
  Resend = 465) waardoor ALLE auth-mail (ook v1 magic-links) hing → GoTrue 504. Bij de fix-poging
  bleek de Management API een partial PATCH op smtp_* als groeps-reset te behandelen; de custom
  SMTP-config is gewist en de Resend-key is nergens lokaal/Vercel terug te vinden (admin- én
  backend-envs hebben lege RESEND_API_KEY). Tussentijds draaide het project op de ingebouwde
  Supabase-mailer. OPGELOST (Thierry, 2026-06-12): nieuwe Resend-key, custom SMTP terug op
  smtp.resend.com:465, domein verified; live OTP-mail getest — aflevering én
  {{ .Token }}-rendering werken.
- Magic-link-mailtemplate had GEEN {{ .Token }} (alleen ConfirmationURL) — de e-mail+code-flow
  van E01.6 kon dus nooit werken. Template uitgebreid met code-blok ({{ .Token }}, eigen huisstijl)
  naast de bestaande knop, dus v1-link-flow blijft werken.
- Mismatch-pad: /v1/auth/send-recovery-email is NIET gedeployed (404 op productie; bestaat als
  niet-gecommit v1-werk in de hoofd-checkout). Handler lokaal gedraaid (tsx-driver): 400 bij
  invalid e-mail, generiek 200 voor onbekend én bestaand adres (anti-enumeratie klopt). E2E-test
  kan pas na v1-deploy van dat endpoint.
- URL-scheme: aaavatar (CFBundleURLTypes) toegevoegd aan Avatar2-target in project.yml; backend
  stuurt hardcoded aaavatar://stripe-return|stripe-cancel. Geverifieerd in gebouwde Info.plist.
  Let op: v1 en v2 registreren hetzelfde scheme — LaunchServices kiest er één per machine.

**Result:** Identiteitstest geslaagd (OTP-login op beide bestaande Google-users → zelfde Supabase user-id, Pro behouden via /v1/account); aaavatar-URL-scheme op Avatar2 (project.yml, geverifieerd in Info.plist); recovery-handler lokaal groen (endpoint wacht op v1-deploy); productie-SMTP-bug (poort 462) gevonden en opgelost — custom SMTP hersteld op smtp.resend.com:465 met nieuwe Resend-key (domein verified), live OTP-mail getest incl. {{ .Token }}-codeblok in het magic-link-template; beide targets + tests groen.

## 1.8 — SHARED: Avatar (v1) target linkt AvatarKit
- status: done
- owner: INFRA
- blockedBy: 1.2
- DoD: beide targets bouwen, tests groen

Nodig voor E02.2 (AI): EdgeBenchmark leeft in `Avatar/Debug/` en moet `VisionCutoutEngine` uit
AvatarKit als 5e arm kunnen aanroepen. Alleen project.yml: package-dependency `AvatarKit` op de
targets `Avatar` en `Avatar-MAS`; geen v1-codewijzigingen. (Story toegevoegd door AI bij
oplevering E02.1 — project.yml is INFRA-grens.)

**Result:** Al vervuld door E01.5: project.yml had de AvatarKit-package-dependency al op de targets Avatar én Avatar-MAS (naast Avatar2). Geverifieerd op v2-main: xcodegen + Avatar, Avatar-MAS en Avatar2 bouwen Debug groen, alle package-tests groen; geen v1-codewijzigingen. E02.2 (AI) is hiermee gedeblokkeerd.


## 1.9 — Avatar2 unit-test-target
- status: done
- owner: INFRA
- blockedBy: 1.1
- DoD: beide targets bouwen, tests groen

App-target-logica (bv. OnboardingModel uit E04.1: e-mailvalidatie, stap-state, skip/finish — en
straks de auto-verify-logica van E04.2) is nu alleen build-gedekt: er is geen unit-test-target
voor Avatar2. Toevoegen via project.yml (Avatar2Tests, XCTest, host Avatar2) + opnemen in
scripts/build-v2.sh. (Story toegevoegd door FEAT bij oplevering E04.1 — project.yml is
INFRA-grens.)

**Result:** Avatar2Tests-target (bundle.unit-test, gehost in Aaavatar 2.app) via project.yml, incl. expliciete PRODUCT_MODULE_NAME=Avatar2 (PRODUCT_NAME bevat een spatie) en scheme-testTargets op Avatar2; 9 OnboardingModel-unit-tests (stap-overgangen, e-mailgate, code-gate, completion-persistentie — Supabase-paden bewust buiten bereik); teststap opgenomen in scripts/build-v2.sh; beide targets bouwen groen, alle suites groen (Avatar2Tests 9/9, AvatarKit 31, AvatarUI 1).

## 1.10 — Model-override-parameter + MODEL_REGISTRY [backend]
- status: ready
- owner: —
- blockedBy: —
- DoD: beide targets bouwen, tests groen
- Context: backend/lib/replicate.ts (gepinde model-versies per feature); isDevUnlimitedUser-gate bestaat in backend/lib. Voer voor E15.5 (dev-model-picker) en testmechanisme voor E09.1. (Story toegevoegd op besluit Thierry 2026-06-12.)

Backend-endpoints (cutout/colorize/fill-body, straks stylize) krijgen een optionele
model-override-parameter, uitsluitend gehonoreerd via de bestaande `isDevUnlimitedUser`-gate, met
een whitelist per endpoint (geen vrije slugs — alleen geregistreerde alternatieven). Model-slugs
en gepinde versies verhuizen uit de losse constanten naar één `MODEL_REGISTRY` in `backend/lib`,
zodat override-whitelist, credit-tarief (E14.3) en `requiresCloud` per feature op één plek leven.

**Result:** _(invullen bij done)_
