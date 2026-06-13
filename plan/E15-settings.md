# E15 — Settings volledig

Team: **FEAT**

Vervangt E08.1 (barebones). Figma heeft nu twee voorbeeld-frames: 'App / Settings / Preferences' en 'App / Settings / AI & Models' (sectie Settings, node 4017:10181). Patroon: sub-nav links (4 items) + content rechts met Settings-secties. **Besluit Thierry: de rest van de pagina's zelf invullen in dezelfde stijl.**

## 15.1 — Settings-shell + Preferences
- status: done
- owner: AI (op directe instructie Thierry 2026-06-12 — E15 in volgorde 15.1→15.4, ondanks FEAT-epic)
- blockedBy: E03.2
- DoD: beide targets bouwen, tests groen
- Context: Figma 'App / Settings / Preferences' (4019:497); componenten Navigation Button/Setting Row uit Components-pagina.

Venster met sub-nav (4 items) + content-area, conform Figma. Preferences-pagina: Appearance- en
Notifications-secties zoals ontworpen.

Notities (AI, bij oplevering):
- Sub-nav-items = de vier E15-pagina's (Preferences/AI & Models/Account/About); het frame
  toont nog "Permissions" uit de template-app — gedocumenteerde afwijking conform het bord.
- Credits/Upgrade-strip + gear uit het frame zijn hoofdvenster-patroon (elk App-frame draagt
  ze); dit venster is gescoped op sub-nav + content zoals de story zegt. Traffic lights
  inline (hiddenTitleBar), nav én header op y76 zoals de shell.
- Notifications-rij: frame draagt transcribe-template-copy ("Recording reminder…"); vorm
  1-op-1, copy in de geest van Aaavatar ("Update notifications", persistent
  settings2.updateNotifications — 15.4/Sparkle consumeert hem).
- Theme-voorkeur (System/Light/Dark) persistent (settings2.appearance) en toegepast op beide
  scenes; tokens zijn dark-only dus het directe effect is systeemcontrols — licht thema is
  later puur tokenwerk.
- Navigation Button/Setting Row/sectiekaart zijn lokale views in Features/Settings/ — niet
  in AvatarUI (DS-grens); DS kan ze desgewenst liften via een eigen story.
- Visuele smoke-run kon bij oplevering niet betrouwbaar (tweede debug-instantie naast actieve
  gebruikerssessie); alsnog gedaan bij visuele-pass punt 14.
- Herzien door visuele-pass punt 14 (zelfde dag): de aparte Settings-scene is vervangen door
  een in-window view-state in ShellView (gear toggelt met active-state, Esc sluit, topbar
  blijft staan) — conform de frames die het hele app-venster vullen. Screenshots geverifieerd
  tegen 4019:497, incl. pill-dropdown en meekrimpende sectiekaarten.

**Result:** Settings-venster (SwiftUI Settings-scene, hiddenTitleBar, 1000×700) in Avatar2/Features/Settings/ — SettingsRootView (sub-nav 320 met SETTINGS-kop + 4 Navigation Buttons incl. action-balkje/hover, content 656), SettingsPreferencesPage (H1-header, Appearance-sectie met System/Light/Dark-dropdown op DS-tokens, Notifications-sectie met icoonrij + DSToggle), sectie/rij als herbruikbare lokale views; gear werkt nu via showSettingsWindow:; beide targets bouwen groen, packagetests groen.

## 15.2 — AI & Models-pagina
- status: done
- owner: AI (E15-reeks op directe instructie Thierry)
- blockedBy: 15.1, E02.3
- DoD: beide targets bouwen, tests groen
- Context: Figma 'App / Settings / AI & Models' (4019:823); ModelManager-vereenvoudiging uit E02.3. Let op: waveform-icoon in design is placeholder — gebruik cloud/sparkle.

Notities (AI, bij oplevering):
- PrivacyPreferences2 (Avatar2/Features/Settings/) draagt de v1-keys/rawValues incl.
  fingerprint-beleid; E04.3 (onboarding-privacy-stap) kan hem direct hergebruiken.
- OrmbgModelStore.download kreeg een optionele voortgangscallback (AvatarKit/Engines,
  AI-grens): bytes-stream naar schijf met fractie per 256 KB-chunk; zonder callback
  ongewijzigd gedrag. Geslaagde download activeert de engine meteen; trash zet terug naar
  Apple Vision.
- Router-wiring: ShellModel registreert nu Vision + ORMBG en prefereert de engine-voorkeur
  per import (terugval = eerste beschikbare = Vision) — de Active-state is dus echt.
- Frame-afwijkingen gedocumenteerd in de code: headernode draagt "Preferences"
  (template-bug) → "AI & Models"; waveform → cloud-glyph; echte modelwaarden (78 MB —
  niet de ±175 MB uit figma-design-review.md; "8 GB RAM" uit het frame klopt voor elke
  ondersteunde Mac).
- Visuele check geblokkeerd: een Xcode-debug-instantie van Aaavatar 2 (Thierry) hield de
  bundle-id bezet en assistive access voor osascript is ingetrokken. DEBUG-launchhaak
  toegevoegd: `open "Aaavatar 2.app" --args --show-settings aiModels` opent de pagina
  direct — check kan zodra de debugsessie vrij is.

**Result:** AI & Models-pagina in Avatar2/Features/Settings/ (SettingsAIModelsPage): online-modellen-toggle op PrivacyPreferences2 (zelfde keys/rawValues/fingerprint-beleid als v1, klaar voor E04.3), Local models-kaart met High-fidelity edges op OrmbgModelStore — download met lineaire voortgang + percentage, Active-state gekoppeld aan de engine-voorkeur, delete → terugval Apple Vision; ShellModel-router gebruikt de voorkeur per import; beide targets bouwen groen, packagetests groen.

'Allow online models'-toggle (zelfde PrivacyPreferences als onboarding) + Local models-lijst (naam •
RAM-eis • grootte, Active-state, download/delete via icon-button). Hier landt de High-fidelity
edges-download (was E04.4/E08.1).

Bevestigd (besluit Thierry 2026-06-12, vervolg op de ORMBG-herziening): de downloadkaart +
voortgangsweergave **blijft**, gevoed door dezelfde `OrmbgModelStore` (E02.3) als de
onboarding-downloadstap (E04.6) — één download-state, twee vensters erop. Een download die
in onboarding gestart is loopt hier zichtbaar door (achtergrond-download). E05.6 (nudge na
rafelig haarresultaat) hangt hier ook op.

**Result:** _(invullen bij done)_

## 15.3 — Account-pagina (zelf invullen)
- status: backlog
- owner: —
- blockedBy: 15.1, E14.1
- DoD: beide targets bouwen, tests groen
- Context: stijl uit 15.1; gegevens via AvatarKit (AuthService, ProEntitlement).

In dezelfde stijl: e-mail, plan (Starter/Pro) + Manage subscription, credits-saldo + resetdatum,
sign out. Geen design — extrapoleer Setting Row-patroon.

**Result:** _(invullen bij done)_

## 15.4 — About/Updates-pagina (zelf invullen)
- status: in_progress
- owner: AI (E15-reeks op directe instructie Thierry; 15.3 overgeslagen — blocked op E14.1)
- blockedBy: 15.1
- DoD: beide targets bouwen, tests groen
- Context: v1 UpdatesSection als functionele referentie; appcast.

Versie, updatekanaal, check-for-updates (Sparkle), links (privacy, site). Zelfde patroon.

**Result:** _(invullen bij done)_

## 15.5 — Advanced-sectie (dev-only model-picker)
- status: backlog
- owner: —
- blockedBy: 15.2, E01.10
- DoD: beide targets bouwen, tests groen
- Context: model-override-API uit E01.10; AI & Models-pagina uit 15.2. Dit is ook het testmechanisme voor de E09.1-bakeoff. (Story toegevoegd op besluit Thierry 2026-06-12.)

"Advanced"-sectie in Settings > AI & Models, alleen zichtbaar voor dev-accounts
(isDevUnlimitedUser): model-picker per cloud-feature (whitelist uit E01.10) en engine-keuze per
lokale feature. Keuzes persistent, duidelijk gemarkeerd als dev-only. Geen zichtbaarheid of
gedrag voor reguliere gebruikers. Deploy: MODEL_REGISTRY/model_override staan sinds de E13.0-port
van 2026-06-12 op productie; backend-werk dat daarna op v2-main landt in-app testen tegen een
**Vercel-preview-deploy** tot de volgende port.

**Result:** _(invullen bij done)_
