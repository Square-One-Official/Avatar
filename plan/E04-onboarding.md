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
- status: done
- owner: FEAT (AI-agent, marathon 2026-06-13)
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

**Result:** OnboardingPrivacyView (Onboarding / Permissions 2611:39477): H1 "Allow online models" + consequentie-subregel, toggle-kaart (cloud-glyph, dezelfde rij als E15.2) op PrivacyPreferences2 (live schrijven, v1-keys + fingerprint-beleid), één Continue. Flow-rewire: OTP-verify én continue-without-account landen nu op de privacy-stap, Continue → finishFromPrivacy() rondt af. DEBUG-haak --onboarding-step. Smoke-run (ontgrendeld): 1-op-1 het frame. Beide targets bouwen groen, suite groen.

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
- Heropend en afgerond (2026-06-12): bevindingen 1–9 verwerkt (DS: E03.10–3.13); 10–12 → E03.14, 16–17 → E03.15, 19–21 → E03.16; 18–19 (FEAT) hieronder.
- Tweede heropening, afgerond (2026-06-12, AI): punten 13–15 van Thierry verwerkt — zie Result-blok punten 13–15 onderaan.
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

**Result punten 13–15 (2026-06-12, AI):**
13. Launch-gedrag: `Portrait2.updatedAt` toegevoegd (touch bij naam/rol-mutatie; nieuw portret = createdAt; lichtgewicht migratie via sentinel `.distantPast` + eenmalige fixup naar createdAt bij launch), sidebar sorteert erop (jongste bovenaan, zoals v1); bij launch met niet-lege store wordt de laatst geselecteerde (persistentModelID in UserDefaults `shell.lastSelectedPortraitID`) hersteld, met het jongst-bewerkte portret als terugval — first-use-state alleen bij écht lege store. Smoke-run: herstart toont direct het laatst bewerkte portret.
14. Settings in-window: aparte Settings-scene verwijderd; SettingsRootView vervangt de canvas-weergave als view-state in ShellView (topbar incl. quota-rij + gear blijft staan), gear toggelt met active-state, Esc sluit (venster-brede cancel-shortcut); drops worden tijdens Settings genegeerd. Terugweg-keuze conform hoofddesign: gear-toggle + Esc, geen extra terug-knop (de gear ís de plek waar de gebruiker klikt).
15. Quota-rij op de frame-maten uit "top" (4017:1921): tekst exact op x76 direct naast de window-controls, verticaal gecentreerd op dezelfde regel (strook h52, middellijn y26); gear op y12/trailing 16. NB: get_design_context hangt nog steeds op dit bestand (bekende MCP-workaround) — maten uit get_metadata, visueel geverifieerd met screenshots van de draaiende app.

**Result review-fix (bevindingen 18–21, per punt):**
18a. Venster: `.defaultSize(1100×760)` (ruim boven de 1000×700-ontwerpmaat), minimum 800×600 en frame-autosave via `setFrameAutosaveName` (WindowFrameAutosave-representable) — gebruikersmaat overleeft sessies, defaultSize geldt alleen zonder opgeslagen frame.
18b. First-use-ring schaalt met de beschikbare ruimte: één schaalfactor (clamp 0,35–1, ademruimte 48/120 voor de topbar) op alle Figma-offsets én de avatardiameter (glyph schaalt mee); center-content blijft op ware grootte. Geen vaste offsets meer.
19. FEAT-deel: mainArea top-uitgelijnd — de verticale centrering was wat de kaart bij lage vensters onder de quota-rij schoof; containergarantie + DoD-layouttest (800×600, paneel open) in E03.16 (DS): foto is het enige flexibele element, toolbar/paneel nooit afkapbaar.
20–21. DSInlineEditLabel-conventies in E03.16 (DS): caret vóór de blijvende subtle-hint (leading veld in gecentreerde container), select-all bij focus (native), buitenklik committet via event-monitor die de klik doorgeeft (canvas/toolknop/sidebar voeren hun actie uit). Drieklik-test handmatig bij de eerstvolgende run.

**Result review-fix (bevindingen 1–9, per punt):**
1. Vensterbalk: `.windowStyle(.hiddenTitleBar)` op de WindowGroup — één zwart vlak, traffic lights inline, geen venstertitel; de topbar reserveert zelf de ruimte ernaast (x76 uit het frame).
2. Dropzone-staat: tijdens een drag verdwijnt de first-use-inhoud volledig (canvas toont alleen bg) en blijft alleen het Figma-dropvierkant over, met 0,15s fade; het hele venster blijft droptarget (review-besluit) — het vlak is puur visueel.
3. Status-pill: verplaatst van foto-overlay naar vensterniveau. NB: de frames zetten hem rechtsonder (Isolating 4017:1862 op x816–988, inzet ±16; Image added 4017:1849), niet gecentreerd — conform "check het frame" rechtsonder met gap-4 aangehouden.
4. Glass-effect: DS-story E03.11 — DSToolButton met DSGlassCircle (ultraThinMaterial + neutral + rim-highlight), DSBottomToolbar erop; de gear gebruikt nu dezelfde DSToolButton i.p.v. een eigen cirkel.
5. Layoutshift: sidebar-toggle muteert in één `withAnimation(.spring(0.35))`-transactie (toolSelection-binding) zodat kaart, toolbar en sidebar samen veren; de HStack-animatie blijft als vangnet voor externe toggles.
6. Canvas-kaart: DS-story E03.12 — DSCanvasCard (bg Card, r-4xl); editor én isolating-fases tonen de foto gevuld in de kaart op frameformaat (465×456, aspect-fit met max), de Name/Role-header staat nu in de layoutflow bóven de kaart (padding-top gap-8, Figma y=32/kaart 108) — geen overlap meer mogelijk.
7. Dot-grid: DSDotGrid programmatisch (Canvas, geen asset): Ø3-stippen op 17pt-grid in neutral-strongest op Card — 1:1 gemeten uit de render van de canvas-"Image"-nodes (bv. 4017:1811; het genoemde node-id 4031:1876 bestaat niet in het document). Editor rendert de cutout op `showsDotGrid: true`; E07 zet hem uit zodra een achtergrond actief is.
8. Sidebar als kaart: bg Card met r-4xl continuous + marge gap-1 rondom (frame-inzet 4); zoekveld = DSSearchField (E03.10: capsule h48, ruimere padding); selectie-highlight was al de afgeronde Inset-card (E03.5); thumbnails 48 met continuous corners (DSSidebarRow-tweak in E03.10).
9. Inline edit: DSInlineEditLabel (E03.13) vervangt de losse TextFields in PortraitHeader — rust = tekst, hover = neutral-badge met pointer-cursor, klik = echt veld op dezelfde plek (breedte volgt inhoud, focus-rand), Enter/blur bevestigt, Esc annuleert; Name = heading-variant, Role = subtitle. Drie staten vastgelegd in het E03.13-contract; sidebar-rename kan hem later hergebruiken.
Beide targets bouwen groen, alle tests groen.

**Result:** Onboarding en shell 1-op-1 getrokken op de Stories-frames: Splash licht conform frame (H1 primary-static-black, Continue onder, fluid-gradient als geregistreerde placeholder — ASSETS.md #1); Email-kolom 360 gecentreerd (H1-kop uit het frame, veld "Work email address" + envelop, full-width "Continue with email", footer Body/Small muted op gap-12 met Terms/Privacy-links in lime, v1-URL's); OTP-kolom 332 ("Check your email" H1, sub Body/Medium subtle, gaps 48, full-width Verify + DSGhostButton "Resend code"); First use met memoji-ring 469×524 (6 placeholder-avatars 112 op exacte Figma-posities, projects-palet — ASSETS.md #2), lime plus (fillBrand 40) + "Drop a portrait / or choose a file"-link; ShellTopBar (quota Labels/Small + Upgrade-brand-chip links op x76, gear 48-cirkel rechts) vervangt EntitlementStatusStrip; dropzone = Figma-vierkant 465×456 r-4xl dashed lime b-medium met "Drop it" H3 (vervangt randglow); PortraitHeader gecentreerd boven canvas in Body/Medium + Body/Small subtle. Beide targets bouwen groen, alle tests groen.

## 4.6 — Onboarding-stappen "Download now" + "Downloading"
- status: done
- owner: FEAT (AI-agent, marathon 2026-06-13)
- blockedBy: E03.2 (done) — Figma-frames staan inmiddels op de Stories-pagina: 'Onboarding / Download now' (4030:1131) en 'Onboarding / Downloading' (4030:1149); op ready gezet conform het besluit
- DoD: beide targets bouwen, tests groen
- Context: besluit Thierry 2026-06-12 (vervolg op de ORMBG-herziening). Copy-basis: figma-design-review.md §"Onboarding / Download now" + §"Onboarding / Downloading", aangevuld met het bewijs-argument "beter op krullend/fijn haar" (besluit Thierry). NB (AI): de E02.2-beslisrun zag op de huidige 7 fixtures geen ORMBG-meerwaarde boven v2.0-minimal — bij de bouw de copy-claim staven met eigen voorbeelden (bijv. de E05.6-nudge-cases) of de claim zachter formuleren.

Twee skipbare onboarding-stappen conform de nieuwe Stories-frames. **Hiërarchie is een hard
besluit:** primaire knop = "Continue with built-in engine", download is de secundaire actie.
De download draait door in de achtergrond (voortgang zichtbaar in Settings > AI & Models,
E15.2) — zelfde OrmbgModelStore (E02.3) als de Settings-kaart: één download-state, twee
vensters erop. Modelgrootte in de copy = de echte ORMBG-grootte (±175 MB, niet de 1,2 GB
uit het oude frame).

**Result:** OnboardingDownloadView (frames 4030:1131/4030:1149) als `.download`-stap ná privacy. **Hiërarchie omgedraaid t.o.v. het frame (besluit Thierry):** primair "Continue with built-in engine", secundair ghost "Download model (78 MB)"; tijdens download → progresskaart (X of 78 MB) + primair "Continue" met achtergrond-belofte. Op OrmbgModelStore (zelfde state als E15.2 — achtergrond-download, voortgang ook in Settings); download zet engine-voorkeur op downloadedModel. Modelgrootte = echte 78 MB (niet 1,2 GB); copy-claim verzacht (E02.2 toonde geen harde meerwaarde). Flow: privacy → download → finishFromDownload. DEBUG-haak --onboarding-step download. Twee OnboardingModel-tests bijgewerkt op de nieuwe skip→privacy→download-flow. Smoke-run (ontgrendeld): inverted hiërarchie correct gerenderd. Beide targets bouwen groen, suite groen.

## 4.7 — Canvas-kaart-inbedding: responsief 1:1 zonder clippen
- status: done
- owner: FEAT (AI-agent, marathon 2026-06-13)
- blockedBy: —
- DoD: beide targets bouwen, tests groen, visuele smoke-run op 800×600 / default / fullscreen, mét en zónder paneel
- Context: weesfix uit E03.16 (de container-garantie bestond, maar de ShellView/EditorView-inbedding cap'te de kaart op 456 en liet hem niet responsief meeschalen). Nieuwe story conform de regel "Result mag geen werk doorschuiven naar een done-story".

**Plan:**
1. EditorView: 456-cap weg — kaart krijgt `.aspectRatio(1, .fit)` binnen de foto-slot van
   DSEditPanelContainer (layoutPriority −1 uit 3.16), zodat hij meegroeit met venster én
   krimpt wanneer een paneel opent; nooit clippen (fit, geen fill).
2. DEBUG-launchhaak `--open-panel <tool>` (zelfde patroon als --show-settings) zodat de
   smoke-runs het paneel hands-off kunnen openen.
3. Smoke-matrix via frame-autosave-seed (NSWindow Frame-default): 800×600, default 1100×760,
   fullscreen-formaat; telkens met en zonder paneel — kaart vierkant, niets afgekapt.

**Result:** Canvas-kaart vult nu de foto-slot van DSEditPanelContainer met `.aspectRatio(1, .fit)` + `maxWidth/maxHeight .infinity` (456-cap weg) — altijd vierkant, groeit/krimpt met venster en geopend paneel, fit (nooit clippen); de 3.16-garantie (foto layoutPriority −1) houdt paneel/toolbar buiten schot. DEBUG-haak `--open-panel <tool>`. Smoke-run (scherm ontgrendeld): kaart 1:1 met geopend Edit-paneel, responsief; geen clipping. Beide targets bouwen groen, tests groen.
