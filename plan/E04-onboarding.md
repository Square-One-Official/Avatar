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
  de Stories-frames → verplaatst naar story 4.5.
- Splash is dark (niet het lichte Figma-moment): de review markeerde de licht→donker-overgang
  als onopgelost; tot dat designbesluit valt blijft de flow dark-only.
- Na e-mail verstuurd → tijdelijke "Check your inbox"-landing met skip-escape; E04.2 vervangt
  die door de echte OTP-stap.
- OnboardingModel-logica (e-mailvalidatie, stap-state, skip/finish) is alleen build-gedekt:
  er bestaat geen unit-test-target voor de Avatar2-app — story E01.9 (INFRA) toegevoegd.

**Result:** Onboarding-flow (Splash → Email → code-verstuurd-landing) in Avatar2/Features/Onboarding/ op AuthService.requestCode + DSTextField/DSPrimaryButton; incl. continue-without-account (persistent via onboarding2.completed), RecoverPro-hint en review-copy; gemount in Avatar2App achter onboarding.isActive; beide targets bouwen groen, alle packagetests groen, smoke-run 0% idle-CPU.

## 4.2 — OTP-stap
- status: done
- owner: FEAT
- blockedBy: 4.1
- DoD: beide targets bouwen, tests groen

Auto-verify bij 6e cijfer, disabled-state, 'Wrong email? Go back'-link.

Notities (FEAT, bij oplevering):
- Resend-link in foreground/subtle i.p.v. het lage contrast uit het oorspronkelijke frame
  (review-fix); resend-bevestiging als inline tekstregel.
- Auto-verify én Verify-knop: dubbele triggers onschadelijk via de isBusy-gate in
  canVerifyCode. Bij een foute code blijft de invoer staan om te corrigeren.
- Logica blijft alleen build-gedekt tot E01.9 (Avatar2-testtarget, INFRA) landt.
- Live e-mail-verify niet in deze sessie getest; SMTP-pad is door INFRA al live geverifieerd
  (E01.7-notities) — end-to-end-check kan bij de eerste handmatige run.

**Result:** OTP-stap in Avatar2/Features/Onboarding/ (OnboardingOTPView op DSOTPField + AuthService.verifyCode): auto-verify bij het 6e cijfer, Verify-knop met disabled-state, Resend code met bevestiging, 'Wrong email? Go back'; geslaagde verify rondt onboarding af; stub-landing uit 4.1 verwijderd; beide targets bouwen groen, alle packagetests groen.

## 4.3 — Privacy-stap
- status: ready
- owner: —
- blockedBy: E03.2, E03.6
- DoD: beide targets bouwen, tests groen

Online-modellen-toggle met inline consequentie-uitleg, één Continue-knop. Schrijft dezelfde
PrivacyPreferences als v1.

Notities (FEAT, vóór de bouw):
- Geblokkeerd op nieuwe story E03.6: AvatarUI heeft nog geen toggle/switch-component.
- "Dezelfde PrivacyPreferences als v1" = dezelfde UserDefaults-keys/rawValues (aiPrivacyMode,
  localCutoutEngine, shareAnonymousDiagnostics) in het eigen defaults-domein van Avatar2 —
  v1's klasse leeft in Avatar/Services/ (verboden terrein) en de bundle-id's verschillen,
  dus de plist kan nooit letterlijk gedeeld zijn. Incl. fingerprint-beleid (localOnly →
  ephemeral DeviceFingerprint, zit al in AvatarKit).
- Flow-rewire bij de bouw: OTP-verify én skip-pad landen straks op de privacy-stap i.p.v.
  direct afronden.

**Result:** _(invullen bij done)_

## 4.4 — High-fidelity edges naar Settings
- status: backlog
- owner: —
- blockedBy: E08.1
- DoD: beide targets bouwen, tests groen

Downloadkaart in barebones Settings (E08.1) — onboarding bevat hem niet meer.

**Result:** _(invullen bij done)_


## 4.5 — Visuele pass onboarding + shell tegen Stories-frames
- status: in_progress
- owner: FEAT
- blockedBy: E03.1
- DoD: beide targets bouwen, tests groen
- Context: Stories-pagina node 151:1409; werkregel Figma-1-op-1 + placeholder-regel (CLAUDE.md → Vaste kennis, besluit Thierry 2026-06-12).

Gebouwde onboarding (4.1/4.2) en main-shell-delen naast de echte Stories-frames leggen en
1-op-1 trekken: spacing, formaten, states, interacties en animaties. Assets als gemarkeerde
placeholder op de juiste afmetingen/verhouding, geregistreerd in plan/ASSETS.md (o.a.
splash-achtergrond, memoji-cirkel). Visuele afwijkingen alleen met expliciet besluit van
Thierry, gedocumenteerd in de story.

Hierheen verplaatst (losse 'visuele pass'-vermeldingen):
- Uit 4.1-notities: "Visuele pass tegen de Stories-frames nog doen zodra Figma open staat."
- Uit E08.3-notities: paywall-barebones is zonder Figma-frame opgebouwd uit DS-componenten,
  "visuele pass later" — het Pro-modal-frame bestaat inmiddels (4019:953); de paywall-pass
  loopt via E14.1 (pixel-volgen), niet via deze story.

**Result:** _(invullen bij done)_
