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
- status: ready
- owner: —
- blockedBy: 1.2, 1.3
- DoD: beide targets bouwen, tests groen

Testtargets voor AvatarKit en AvatarUI, één smoke-test, xcodebuild-script dat beide apps + tests
draait.

**Result:** _(invullen bij done)_

## 1.5 — SHARED: BackendClient naar AvatarKit
- status: ready
- owner: —
- blockedBy: 1.2
- DoD: beide targets bouwen, tests groen

BackendClient (auth/entitlement/cloud-calls) verplaatsen naar AvatarKit; oude app consumeert hem
vandaaruit. Enige story die Avatar/ mag raken.

**Result:** _(invullen bij done)_

## 1.6 — Auth 2.0: e-mail + code
- status: ready
- owner: —
- blockedBy: 1.2
- DoD: beide targets bouwen, tests groen

Nieuwe AuthService in AvatarKit op Supabase signInWithOTP/verifyOTP. Geen OAuth/PKCE/deep-link voor
auth. Backend auth.ts ongewijzigd. Google-infra blijft bestaan maar krijgt geen UI in 2.0.

**Result:** _(invullen bij done)_

## 1.7 — Stripe/identiteit-verificatie OTP-switch
- status: backlog
- owner: —
- blockedBy: 1.6
- DoD: beide targets bouwen, tests groen

Test: OTP-login op e-mail van bestaande Google-user → zelfde Supabase-user (Pro behouden). Test
mismatch-pad → RecoverPro (send-recovery-email). URL-scheme behouden voor stripe-return/cancel.
Google-infra NIET slopen.

**Result:** _(invullen bij done)_

