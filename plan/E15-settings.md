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
- Visuele check alsnog gedaan (debugsessie vrijgekomen): pagina rendert 1-op-1 het frame
  (cloud-glyph, toggle, modelkaart 78 MB + download-knop). DEBUG-launchhaak
  `--show-settings <pagina>` blijft beschikbaar voor latere smoke-runs.

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
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 15.1, E14.1
- DoD: beide targets bouwen, tests groen
- Context: stijl uit 15.1; gegevens via AvatarKit (AuthService, ProEntitlement).

In dezelfde stijl: e-mail, plan (Starter/Pro) + Manage subscription, credits-saldo + resetdatum,
sign out. Geen design — extrapoleer Setting Row-patroon.

**Result:** SettingsAccountPage (Features/Settings/), geëxtrapoleerd in de 15.1-stijl (SettingsSectionCard/SettingsRow): Account-sectie (e-mail uit AuthService; Plan-rij = "Starter" + Upgrade-chip → paywall, of "Manage subscription" → Stripe-portal voor Pro), Credits-sectie (saldo + resetdatum/`monthlyResetAt`), Session-sectie met Sign out (alleen ingelogd). Data via nieuwe EntitlementModel-passthroughs (accountEmail/isSignedIn/planLabel/signOutAccount/openManageSubscription); SettingsRootView(entitlement:) gethread vanuit ShellView. DEBUG-haak --show-settings account. Smoke-run (ontgrendeld): pagina rendert in 15.1-stijl (signed-out state correct: e-mail "—", Sign out verborgen). Beide targets bouwen groen, suite groen.

## 15.4 — About/Updates-pagina (zelf invullen)
- status: done
- owner: AI (E15-reeks op directe instructie Thierry; 15.3 overgeslagen — blocked op E14.1)
- blockedBy: 15.1
- DoD: beide targets bouwen, tests groen
- Context: v1 UpdatesSection als functionele referentie; appcast.

Versie, updatekanaal, check-for-updates (Sparkle), links (privacy, site). Zelfde patroon.

Notities (AI, bij oplevering):
- Sparkle is in Avatar2 nog niet gelinkt (project.yml = INFRA-grens) → nieuwe story E01.11
  (ready). Tot die landt is "Check now" bewust disabled; versie-rij en links zijn volledig
  functioneel; auto-check-voorkeur persisteert alvast (settings2.autoUpdateCheck).
- Geen Figma-frame: geëxtrapoleerd in het Setting Row-patroon van 15.1 (Updates- en
  Links-sectie), conform de werkregel.
- Visuele check alsnog gedaan: Updates- en Links-sectie renderen in het 15.1-patroon
  (versie uit de bundle, disabled Check now, werkende link-rijen).

**Result:** About-pagina in Avatar2/Features/Settings/ (SettingsAboutPage): Updates-sectie (versie + build uit de bundle, Automatic updates-DSToggle persistent, Check now-knop disabled tot E01.11/Sparkle), Links-sectie (aaavatar.nl + privacy policy via NSWorkspace); gemount in SettingsRootView; beide targets bouwen groen, packagetests groen.

## 15.5 — Advanced-sectie (dev-only model-picker)
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 15.2, E01.10
- DoD: beide targets bouwen, tests groen
- Context: model-override-API uit E01.10; AI & Models-pagina uit 15.2. Dit is ook het testmechanisme voor de E09.1-bakeoff. (Story toegevoegd op besluit Thierry 2026-06-12.)

"Advanced"-sectie in Settings > AI & Models, alleen zichtbaar voor dev-accounts
(isDevUnlimitedUser): model-picker per cloud-feature (whitelist uit E01.10) en engine-keuze per
lokale feature. Keuzes persistent, duidelijk gemarkeerd als dev-only. Geen zichtbaarheid of
gedrag voor reguliere gebruikers. Deploy: MODEL_REGISTRY/model_override staan sinds de E13.0-port
van 2026-06-12 op productie; backend-werk dat daarna op v2-main landt in-app testen tegen een
**Vercel-preview-deploy** tot de volgende port.

**Plan:**
1. Dev-detectie: account.ts geeft `is_dev_unlimited` mee in de dev-tak (port-only); AccountPayload
   + EntitlementModel.isDevUnlimited. DEBUG-force voor de smoke (productie levert de vlag pas bij
   de volgende port).
2. AvatarKit DevModelCatalog (whitelist-spiegel van MODEL_REGISTRY per cloud-feature) +
   DevModelOverrides (UserDefaults-store, feature→model-key); BackendClient.cutout/colorize/
   fillBody sturen `model_override` mee als de store een keuze heeft (stylize deed dat al).
3. Advanced-sectie in SettingsAIModelsPage, alléén bij isDevUnlimited: Menu-picker per
   cloud-feature + de lokale engine-keuze (PrivacyPreferences2.engine), persistent, gemarkeerd
   dev-only. Geen zichtbaarheid/gedrag voor reguliere gebruikers.

**Result:** Advanced-sectie in SettingsAIModelsPage, alléén bij `entitlement.isDevUnlimited`:
"Advanced" + "Dev only"-badge, lokale Cut-out-engine als chips (Apple Vision / High-fidelity op
PrivacyPreferences2.engine), en per cloud-feature een override-picker (chips) uit de whitelist-
spiegel. AvatarKit: `DevModelFeature` (cutout=[birefnet], colorize=[deoldify], fillBody=
[flux-fill-pro], stylize=[nano-banana, flux-2-pro, gpt-image-1.5]) + `DevModelOverrides`
(UserDefaults `dev.modelOverride.<feature>`); BackendClient.cutout/colorize/fillBody sturen
`model_override` mee als de store een keuze heeft (stylize deed dat al). Dev-detectie:
account.ts geeft `is_dev_unlimited` in de dev-tak (port-only), AccountPayload.isDevUnlimited →
EntitlementModel.isDevUnlimited; DEBUG-haak `--dev-advanced` (gelezen in EntitlementModel.init,
vóór first render). Picker-chips i.p.v. Menu's (Menu's blokkeerden de first-render-window).
Smoke: aiModels-pagina met de Advanced-kaart rendert 1100×760, alle chips + selectie-accent
correct (zie /tmp/e155_aimodels.png). Beide targets bouwen groen, suite groen.

**Smoke-harnas-kanttekening (geen productdefect):** de combinatie van twéé launch-flags
tegelijk — `--dev-advanced` + `--show-settings <pagina>` — laat het hiddenTitleBar-venster bij
opstart naar 33px inklappen (volle schermbreedte, ~0 hoogte). Elke flag los werkt (dev=760,
settings=760), en de Advanced-kaart zelf rendert prima vanaf de first render (`if true`-test =
760). Reguliere gebruikers en échte dev-accounts raken dit nooit: daar wordt `isDevUnlimited`
asynchroon true (account-load) en opent Settings pas op een latere klik — nooit in hetzelfde
opstart-frame. Het zit in de WindowGroup/frame-autosave-setup van Avatar2App (twee concurrerende
autosave-mechanismen + AppearancePreferenceModifier met een per-build-instabiele type-signatuur).
Dat is INFRA-terrein → losse story **E01.14** (zie E01-bestand). Niet-blokkerend voor 15.5.

## 15.6 — Generatie-model-keuze in Settings (nano-banana / OpenAI)
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: E01.10 (MODEL_REGISTRY + override, done), E15.1 (Settings-shell, done)
- DoD: beide targets bouwen + tests groen + gemerged + Result-regel
- Context: besluit Thierry 2026-06-13 (kleding-route); E01.10 MODEL_REGISTRY/override-param;
  E15.2 PrivacyPreferences2-store als voorbeeld; generatie-route uit E10.2/E09.2 (nano = default).
  E15.5 (dev-only Advanced-picker) blijft een apart, technischer pad.

De generatieve cloud-acties (Effects-stijl E09.2, Clothes E10.2, latere stylize-routes) draaien
standaard op nano-banana. Voeg één gebruikersinstelling toe waarmee het generatie-model kiesbaar
is: **nano-banana (default)** of **OpenAI image-model**. Registreer het OpenAI-model in
MODEL_REGISTRY (E01.10) met de juiste override-parameter; de stylize-call leest de voorkeur mee.
Settings-UI: een "Generation model"-rij met twee opties, in de stijl van 15.1/15.2, persistent in
dezelfde Preferences-store. Default ongewijzigd gedrag.

Bewust NIET in deze story: per-actie-override, en de dev-only Advanced-picker (dat blijft E15.5).
Call-wiring leunt op het productie-/v1/stylize uit E09.2 — landt die later, dan registreert deze
story alvast model + Settings-keuze en wordt de call-param aangesloten zodra E09.2 er is.

Acceptatie: model wisselen verandert aantoonbaar de model-param in de /v1/stylize-request;
nano blijft default; beide targets groen + gemerged.

**Plan:**
1. Backend (port-only): OpenAI-model staat al in MODEL_REGISTRY.stylize (`gpt-image-1.5`).
   `USER_SELECTABLE_MODELS` + `resolveGenerationModel(feature, rawKey)` toevoegen (user-facing
   whitelist {nano-banana, gpt-image-1.5}, default/onbekend → null = stil terugvallen). stylize.ts
   precedentie: dev `model_override` > user `generation_model` > default.
2. AvatarKit: `GenerationModel`-enum (rawValue = backend-key) + `GenerationModelStore`
   (UserDefaults, default nano); BackendClient.stylize stuurt `generation_model` mee.
3. FEAT: "Generation model"-kaart in SettingsAIModelsPage (alle gebruikers, niet dev-only):
   twee opties (Nano Banana / OpenAI) met radio-select, persistent via de store.

**Result:** Gebruikersgerichte modelkeuze end-to-end. **Backend** (port-only, preview-test):
`resolveGenerationModel` + `USER_SELECTABLE_MODELS` in models.ts; stylize.ts honoreert
`generation_model` (precedentie dev-override > user-keuze > nano-default); onbekende/verouderde
keys vallen stil terug op nano (geen 400). `npm run typecheck` groen. **AvatarKit:**
`GenerationModel` {nanoBanana="nano-banana", openAI="gpt-image-1.5"} + `GenerationModelStore`
(default nano); BackendClient.stylize stuurt `generation_model` = store-keuze. 3 nieuwe tests
(default = nano, OpenAI persisteert met key `gpt-image-1.5`, round-trip). **FEAT:** "Generation
model"-kaart in SettingsAIModelsPage met Nano Banana (default, checkmark) / OpenAI, persistent.
Smoke (`--show-settings aiModels`): kaart rendert met nano geselecteerd. Beide targets groen,
alle suites groen. Live request-param-wissel verifieerbaar tegen de Vercel-preview (port-only;
landt op productie bij de volgende E13.0-port samen met E09.2's stylize.ts).

## 15.7 — Delete-account-rij
- status: ready
- team: FEAT
- blockedBy: —

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding C7).
**Wat:** `SettingsAccountPage.swift` biedt alleen Email / Plan+Manage subscription /
Credits / Sign out. De backend heeft al `/v1/account/delete` (cancelt Stripe-subs,
wist de Supabase-user, incl. `x-confirm-delete`-header), maar er is géén
client-methode of UI die dit endpoint bereikt. GDPR art. 17-frictie, en bij een
latere Mac App Store-route een harde afwijzing op guideline 5.1.1(v).
**Voorstel:** `BackendClient.deleteAccount()` toevoegen; een destructieve rij in de
Session-sectie met bevestigingsdialoog; na succes `signOutAccount()` + eventueel de
optie de lokale bibliotheek te bewaren of te wissen aanbieden.
**DoD:** beide targets bouwen; delete-account is bereikbaar en werkt end-to-end tegen
een test-account; tests groen; Result-regel.
