# E04 — Onboarding 2.0

Team: **FEAT**

Figma: Onboarding / Splash, Email, OTP, Permissions. Downloadstap is geschrapt (Apple-first). Copy-fixes zijn in Figma verwerkt.

## 4.1 — Splash + Email-stap
- status: done
- owner: FEAT
- blockedBy: E01.6, E03.2
- DoD: beide targets bouwen, tests groen

Alleen e-mail + code, géén Google-knop in 2.0. Incl. continue-without-account-pad en RecoverPro-hint
voor Pro-gebruikers met ander e-mailadres.

Notities (FEAT, bij oplevering):
- Figma was niet bereikbaar (desktop-app had een ander bestand open dan "Aaavatar"); gebouwd op
  de DS-componenten (1-op-1 Figma) + copy-fixes uit figma-design-review.md. Visuele pass tegen
  de Stories-frames nog doen zodra Figma open staat.
- Splash is dark (niet het lichte Figma-moment): de review markeerde de licht→donker-overgang
  als onopgelost; tot dat designbesluit valt blijft de flow dark-only.
- Na e-mail verstuurd → tijdelijke "Check your inbox"-landing met skip-escape; E04.2 vervangt
  die door de echte OTP-stap.
- OnboardingModel-logica (e-mailvalidatie, stap-state, skip/finish) is alleen build-gedekt:
  er bestaat geen unit-test-target voor de Avatar2-app — story E01.9 (INFRA) toegevoegd.

**Result:** Onboarding-flow (Splash → Email → code-verstuurd-landing) in Avatar2/Features/Onboarding/ op AuthService.requestCode + DSTextField/DSPrimaryButton; incl. continue-without-account (persistent via onboarding2.completed), RecoverPro-hint en review-copy; gemount in Avatar2App achter onboarding.isActive; beide targets bouwen groen, alle packagetests groen, smoke-run 0% idle-CPU.

## 4.2 — OTP-stap
- status: in_progress
- owner: FEAT
- blockedBy: 4.1
- DoD: beide targets bouwen, tests groen

Auto-verify bij 6e cijfer, disabled-state, 'Wrong email? Go back'-link.

**Result:** _(invullen bij done)_

## 4.3 — Privacy-stap
- status: backlog
- owner: —
- blockedBy: E03.2
- DoD: beide targets bouwen, tests groen

Online-modellen-toggle met inline consequentie-uitleg, één Continue-knop. Schrijft dezelfde
PrivacyPreferences als v1.

**Result:** _(invullen bij done)_

## 4.4 — High-fidelity edges naar Settings
- status: backlog
- owner: —
- blockedBy: E08.1
- DoD: beide targets bouwen, tests groen

Downloadkaart in barebones Settings (E08.1) — onboarding bevat hem niet meer.

**Result:** _(invullen bij done)_

