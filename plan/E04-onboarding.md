# E04 — Onboarding 2.0

Team: **FEAT**

Figma: Onboarding / Splash, Email, OTP, Permissions. Downloadstap was geschrapt (Apple-first);
besluit Thierry 2026-06-12 (vervolg op de ORMBG-herziening): optionele model-download komt terug
als skipbare stap — zie E04.6. Copy-fixes zijn in Figma verwerkt.

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

## 4.4 — High-fidelity edges naar Settings [VERVALLEN — opgegaan in E15.2]
- status: done
- owner: —
- blockedBy: E08.1
- DoD: beide targets bouwen, tests groen

Downloadkaart in barebones Settings (E08.1) — onboarding bevat hem niet meer.
Vervallen: E08.1 is vervangen door E15 en de downloadkaart staat expliciet in E15.2;
de onboarding-kant is heroverwogen en leeft nu in E04.6.

**Result:** Vervallen zonder implementatie — opgegaan in E15.2 (downloadkaart in AI & Models).


## 4.5 — Visuele pass onboarding + shell tegen Stories-frames
- status: done
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

Notities (FEAT, bij oplevering):
- Buiten de frames maar functioneel behouden, in de geest van het design: foutmeldingen,
  RecoverPro-hint, continue-without-account (Email), dynamisch e-mailadres + 'Wrong email? Go
  back' (OTP). De quota-zichtbaarheidsregel uit E05.1 (pas ná eerste cutout) blijft het
  gedragsbesluit; de vórm is nu 1-op-1 de Figma-topbar.
- Gear-knop stuurt de standaard Settings-selector; functioneel zodra E15.1 de Settings-scene
  levert.
- get_design_context van de lokale Figma-MCP hing op alle frames; geometrie komt uit
  get_metadata (exact) + variabelen uit get_variable_defs + screenshot-pixelmeting (splash).
- E03.9 (full-width-knoppen + DSGhostButton) is hiervoor als DS-story toegevoegd en gedaan.

**Result:** Onboarding en shell 1-op-1 getrokken op de Stories-frames: Splash licht conform frame (H1 primary-static-black, Continue onder, fluid-gradient als geregistreerde placeholder — ASSETS.md #1); Email-kolom 360 gecentreerd (H1-kop uit het frame, veld "Work email address" + envelop, full-width "Continue with email", footer Body/Small muted op gap-12 met Terms/Privacy-links in lime, v1-URL's); OTP-kolom 332 ("Check your email" H1, sub Body/Medium subtle, gaps 48, full-width Verify + DSGhostButton "Resend code"); First use met memoji-ring 469×524 (6 placeholder-avatars 112 op exacte Figma-posities, projects-palet — ASSETS.md #2), lime plus (fillBrand 40) + "Drop a portrait / or choose a file"-link; ShellTopBar (quota Labels/Small + Upgrade-brand-chip links op x76, gear 48-cirkel rechts) vervangt EntitlementStatusStrip; dropzone = Figma-vierkant 465×456 r-4xl dashed lime b-medium met "Drop it" H3 (vervangt randglow); PortraitHeader gecentreerd boven canvas in Body/Medium + Body/Small subtle. Beide targets bouwen groen, alle tests groen.

## 4.6 — Onboarding-stappen "Download now" + "Downloading"
- status: ready
- owner: —
- blockedBy: E03.2 (done) — Figma-frames staan inmiddels op de Stories-pagina: 'Onboarding / Download now' (4030:1131) en 'Onboarding / Downloading' (4030:1149); op ready gezet conform het besluit
- DoD: beide targets bouwen, tests groen
- Context: besluit Thierry 2026-06-12 (vervolg op de ORMBG-herziening). Copy-basis: figma-design-review.md §"Onboarding / Download now" + §"Onboarding / Downloading", aangevuld met het bewijs-argument "beter op krullend/fijn haar" (besluit Thierry). NB (AI): de E02.2-beslisrun zag op de huidige 7 fixtures geen ORMBG-meerwaarde boven v2.0-minimal — bij de bouw de copy-claim staven met eigen voorbeelden (bijv. de E05.6-nudge-cases) of de claim zachter formuleren.

Twee skipbare onboarding-stappen conform de nieuwe Stories-frames. **Hiërarchie is een hard
besluit:** primaire knop = "Continue with built-in engine", download is de secundaire actie.
De download draait door in de achtergrond (voortgang zichtbaar in Settings > AI & Models,
E15.2) — zelfde OrmbgModelStore (E02.3) als de Settings-kaart: één download-state, twee
vensters erop. Modelgrootte in de copy = de echte ORMBG-grootte (±175 MB, niet de 1,2 GB
uit het oude frame).

**Result:** _(invullen bij done)_
