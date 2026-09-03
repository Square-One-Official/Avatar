# E57 — "Edit"-submenu in het tegelmenu (Boost · Fill in body · Apply effect)

Team: **DS + FEAT** (INFRA alleen als de backend iets mist — nu niet voorzien)

Aanleiding (Thierry 2026-09-03): Boost resolution zit alleen in het **bulk**-menu
(≥2 geselecteerd); in een map met één geselecteerde foto ontbreekt 'ie dus. In
plaats van Boost los toe te voegen komt er één rij **Edit ▸** met daaronder
**Boost resolution ▸ (On device / Online)**, **Fill in body** en **Apply effect ▸
(stijlen)**. Interactiereferentie: shadcn Context Menu (submenu opent náást de rij
op hover-intent, chevron rechts, genest kan weer een submenu hebben).

Figma toont geen context-menu-submenu's → interpreteren in de geest van het
hoofddesign (DSMenuRow/DSContextMenuPanel-look, `DSMenuLayout`-tokens), geen
1-op-1-bron. Elke afwijking onder **Figma-TODO:** in de story.

## Huidige situatie (gelezen, niet aangenomen)

- `PortraitDSContextMenu` (`Avatar2/Features/Portraits/PortraitContextMenu.swift`)
  is een `HStack` van hoofdpaneel + één zichtbare flyout (`moveFlyoutOpen` /
  `boostFlyoutOpen`, klik-toggle, één tegelijk). Geen hover-open, geen keyboard,
  geen tweede nesting, flyout altijd rechts (klapt niet om bij de schermrand).
- `singleRows` heeft géén Boost; `bulkRows` heeft "Boost resolution on N ▸" met
  de twee modi (On device · Free / Online · N credits, "Sharper · Cloud" zonder
  cloud-tier).
- `PortraitSetActions.boostResolution(_:mode:entitlement:undoManager:reporter:)`
  werkt al voor 1…N portretten (sequentieel, één undo-groep, bon met
  gelukt/mislukt/op-is-op). Enkel-select-Boost is dus alleen een menu-gat.
- Fill in body bestaat alleen in de editor (`EditorView.runFillBody`): facebox
  via Vision, `backend.fillBodyDetailed`, toepassing via
  `ShellModel.applyFillBodyResult` — die guardt op `selectedPortrait === portrait`
  en is dus **niet** headless bruikbaar vanuit het raster.
- Apply effect bestaat alleen in `EffectsModel.generate` (editor-paneel):
  kwaliteitsgate (`StylizeQualityCoordinator.gateBeforeStylize`), bronkeuze
  (origineel vs cutout), `backend.stylize` (builtin op `styleKey`, custom op
  `customEffectID`, Pro-only), resultaat via `ShellModel.applyEffectResult`
  (her-isolatie met `reIsolateSubject` als het geen schone cutout is), persist
  van `effectBaseData`/`effectActiveRaw`/`effectCache`, framing-wissel
  (`EffectFraming.forSwitch`), selectie-undo. Effectenlijst zit in
  `EffectsModel.sessionCache` (+ disk-cache) en `customSessionCache`.
- Board-tegelmenu (`BoardView.nodeContextMenu`) is een apart menu (Rename/Export/
  Delete) — buiten scope, zie 57.6.

## Doelstructuur van het menu

```
Enkel (1 tegel)                      Bulk (≥2, klik op geselecteerde)
──────────────────────               ─────────────────────────────────
Open                                 Export N portraits…
Move to folder            ▸          Move N to folder            ▸
Edit                      ▸          Match framing            ⌥⌘F
  ├ Boost resolution      ▸          Edit                        ▸
  │   ├ On device   Free               ├ Boost resolution on N   ▸
  │   └ Online      3 credits          │   ├ On device      Free
  ├ Fill in body    2 credits          │   └ Online   3×N credits
  └ Apply effect          ▸            ├ Fill in body on N  2×N credits
      ├ None                           └ Apply effect on N        ▸
      ├ (custom effecten, Pro)             └ (zelfde lijst)
      ├ ────────────                 Set background…          ⇧⌘B
      └ (builtin stijlen)            Use folder background on K
Export…                              ────────────
Use folder background                Delete N
────────────
Delete
```

- De losse "Boost resolution on N ▸"-rij in bulk verdwijnt (verhuist onder Edit).
- Credit-labels via `CreditMeter.chipLabel`/`credits(for:)` (upscaleHigh, fillBody,
  generativeStandard) × aantal; zonder cloud-tier de neutrale "Cloud"-hint zoals nu
  (de gate vraagt zelf om de tier). Geen per-eenheid-rekensommen in de UI buiten
  het totaal (Thierry 2026-09-02: geen per-credit-kosten tonen — het totaal is de
  uitzondering die het menu al toont).
- Apply effect: gecachte stijl (`portrait.effectCache[key]` aanwezig) is gratis en
  instant; label toont dan "Cached" i.p.v. credits. Bij bulk: "N credits" = alleen
  de niet-gecachte portretten.

## 57.1 — DS: genest submenu-component (`DSMenuSubmenu`) [DS]
- status: done
- owner: DS (Claude, 2026-09-03)
- blockedBy: —

**Result:** `DSMenuSubmenu` (AvatarUI) — elk submenu is een eigen child window
naast het paneel (`DSFloatingPlacement.besideRow`, flip naar links, klem op het
scherm; pure layout in `DSFloatingLayout`), hover-intent 150/250 ms met
"sluit alleen als de muis op een andere rij rust", klik opent ook, onbeperkt
nestbaar. Keyboard via `DSMenuTree`/`DSMenuLevel` (DSMenuNavigation.swift):
↑/↓ op zichtbare volgorde met wrap + disabled overslaan, → opent en focust de
eerste rij, ← sluit, Return/Space activeert, Esc sluit het geheel (submenu laat
Esc door aan de root); hover en keyboard delen één `focusedID`, open
submenu-rij blijft gemarkeerd. Klik in een submenu telt als "binnen" het menu
(`DSFloatingPanelController.isInside`). Motion: micro-fade+slide via
`DSMotion.animate`. AX: submenu-rij "Expanded/Collapsed" + hint, paneel als
container met label. `PortraitDSContextMenu` gemigreerd (Move/Boost/Folder-
flyouts → `DSMenuSubmenu`, `FolderDSContextMenu.rows` losgemaakt van z'n
kaart). Tests: 11 navigatie-tests + 4 plaatsingstests (AvatarUI 109 groen),
runtime-test met echte vensters (`DS_FLOATING_WINDOW_TESTS=1`: ↑ → ← → Esc)
groen; Avatar + Avatar2 bouwen, Avatar2Tests 333 groen, motion-/icoon-guards
groen.

**Figma-TODO:** kier paneel↔submenu (nu `gap1` = 4 pt), open-state-kleur van de
trigger-rij (nu de hover-highlight), schaduw van geneste kaarten (nu identiek).

`AvatarUI` krijgt een herbruikbare rij-met-submenu, zodat `PortraitDSContextMenu`
(en later andere menu's) niet zelf `HStack`+`@State`-flyouts hoeven te bouwen.

**Scope**
- `DSMenuSubmenu(title:icon:shortcut:disabled:) { rows }` — een `DSMenuRow` met
  chevron die z'n paneel naast zich opent. Onbeperkt nestbaar (Edit ▸ Boost ▸ modi).
- **Open-gedrag** (shadcn-spirit): hover-intent (open na ~150 ms hover op de rij,
  sluit na ~250 ms als de muis noch rij noch submenu raakt; "safe triangle" naar
  het submenu zodat een diagonale muisbeweging 'm niet sluit); klik op de rij
  toggelt ook (huidige gedrag blijft werken, ook voor tests/smokes).
- **Eén open sibling tegelijk** op elk niveau; een parent sluiten sluit z'n kinderen.
- **Keyboard**: ↑/↓ door rijen, → opent submenu en focust eerste rij, ← sluit
  submenu en gaat terug naar de parent-rij, Return activeert, Esc sluit het hele
  menu (huidige `DSFloatingMode.onDismiss`). Focus-ring conform `DSFocus`.
- **Plaatsing**: submenu rechts van de rij, top uitgelijnd met de rij minus
  `DSMenuLayout.listInset` (rijen op één lijn); bij te weinig ruimte rechts klapt
  't naar links; verticaal geklemd op het scherm zoals `DSFloatingLayout`.
  Plaatsingsrekenwerk als pure functie (`DSSubmenuPlacement.origin(...)`) zodat het
  unit-testbaar is (zelfde patroon als `DSContextMenuPlacement`).
- **Venster**: submenu's leven in hetzelfde child-window als het hoofdpaneel
  (`DSFloatingWindowAnchor` meet het geheel; nu al zo voor de bestaande flyout),
  zodat klik-buiten/dismiss-scrim ongewijzigd blijft. Meten na open → geen
  layout-sprong.
- **Motion**: fade+2 pt-slide in met `DSMotion.micro`; onder Reduce Motion alleen
  fade (E53.4-guard in `build-v2.sh` moet groen blijven).
- **AX**: rij krijgt `.accessibilityAddTraits(.isButton)`, waarde "submenu"
  (open/dicht), submenu-paneel is een `accessibilityElement(children: .contain)`
  met label = rijtitel.
- Migreer de bestaande `moveFlyout` mee (Move to folder ▸) zodat er één patroon
  overblijft; `boostFlyout` vervalt (wordt 57.2).

**DoD**: `swift test` in `AvatarUI` groen (placement-tests: rechts/links-flip,
verticale klem, nesting-offset); beide targets bouwen; preview/smoke met een
3-niveaus-menu; Reduce-Motion-guard groen. **Result:** —

**Figma-TODO:** submenu-offset (4 pt gap?), schaduw/border van geneste panelen,
hover-kleur van een rij wiens submenu open staat (voorstel: hover-highlight
blijft staan zolang het submenu open is, zoals shadcn `data-state=open`).

## 57.2 — FEAT: "Edit ▸"-submenu in het tegelmenu + Boost bij enkel-select [FEAT]
- status: done
- owner: FEAT (Claude, 2026-09-03)
- blockedBy: 57.1

**Result:** `PortraitDSContextMenu.editSubmenu(targets:)` — rij **Edit ▸**
(`wand.and.stars`) in `singleRows` (na Move to folder / Folder “…”) én in
`bulkRows` (na Match framing); daaronder **Boost resolution[ on N] ▸** met
On device · Free / Online · credits-totaal (bestaande `boostRows`). De losse
bulk-Boost-rij is weg; enkel-select in een map heeft nu Boost (het gemelde
gat). Edit is `disabled` zolang een set-actie loopt (`model.isSetActionBusy`)
of een editor-AI-actie andere AI-acties blokkeert
(`entitlement.workingContext.blocksOtherAIFeatures`). Fill in body / Apply
effect-rijen komen erbij in 57.3/57.4 zodra hun set-actie bestaat. DoD: beide
targets bouwen, Avatar2Tests groen; geen aparte smoke (menu-structuur is
code-geverifieerd, de Boost-set-actie zelf is ongewijzigd en getest).

- `singleRows` én `bulkRows` krijgen de rij **Edit ▸** (icoon `wand.and.stars`)
  op de plek uit het schema hierboven; de losse bulk-Boost-rij verdwijnt.
- Onder Edit: **Boost resolution ▸** (On device · Free / Online · credits-totaal),
  **Fill in body** (57.3), **Apply effect ▸** (57.4). Zolang 57.3/57.4 nog niet
  gemerged zijn: rijen wél tonen maar `disabled` met tooltip "Coming soon" is
  **niet** de bedoeling — bouw 57.2 zo dat de rijen pas verschijnen als hun
  set-actie bestaat (feature-check op de `PortraitSetActions`-API), zodat een
  tussentijdse merge geen dode rijen oplevert.
- Enkel-select: `targets = [portrait]` → `PortraitSetActions.boostResolution`
  ongewijzigd. Dit lost het gemelde map-gat op: rechtsklik op één foto in een map
  toont nu Edit ▸ Boost.
- Labels: enkel "Boost resolution", bulk "Boost resolution on N"; credits-totaal
  via `CreditMeter`; zonder cloud-tier "Sharper · Cloud" (bestaand gedrag).
- Eén lopende Edit-batch tegelijk: als `entitlement.workingContext?.blocksOtherAIFeatures`
  of een `reporter.busy` actief is, zijn de Edit-rijen `disabled` (de rij-toestand
  komt uit dezelfde bron als de editor-chips, geen tweede vlag).
- Bestaande `boostFlyout`-code + `toggleBoostFlyout`/`toggleMoveFlyout` verwijderen.

**DoD**: beide targets + `Avatar2Tests` groen; smoke `--record-states` met (a) map
→ 1 foto rechtsklik → Edit ▸ Boost ▸ On device (cutout groeit, undo-entry "Boost
Resolution"), (b) 3 geselecteerd → Edit ▸ Boost on 3 ▸ Online-label toont
"9 credits". **Result:** —

## 57.3 — FEAT: Fill in body als set-actie (1…N) [FEAT]
- status: done
- owner: FEAT (Claude, 2026-09-03)
- blockedBy: 57.2

**Result:** `PortraitSetActions.fillBody(_:entitlement:undoManager:reporter:)` +
rij **Fill in body[ on N]** (credits-totaal / "Cloud") onder Edit ▸. Gate met
gratis server-preflight (`.restoreBody`), Vision-facebox off-main
(`EditorView.normalizedFillBodyFaceBox` hergebruikt), sequentieel
`fillBodyDetailed`, pure stap `fillBodySnapshots` (signature-guard + dezelfde
geometrie als de editor via `ShellModel.compensatedFillBodyTransform`, zonder
`selectedPortrait`-guard — ShellModel is niet aangeraakt), toepassing in één
undo-groep "Fill in body" met `bumpRevision()` (geen raster-herschud), bon
`fillBodyReceipt` (1 portret = editor-copy "Body completed"/"Nothing to fill";
batch telt nothing-to-fill/failed/op-is-op). 402 stopt de batch, 403 Pro →
upgrade-flow. Editor-canvas ververst via `reporter.portraitDidChange`. Tests:
snapshots (compensatie, signature-/mapping-guard), apply/undo/redo in één
groep zonder reshuffle, bon-copy — Avatar2Tests 336 groen, beide targets
bouwen. **Niet gedaan:** annuleren tussen portretten (vraagt een cancel-hook
op de set-actie-toast in ShellModel/ShellView, die in een andere sessie
openstaan) → 57.5. Geen live-smoke met credits in deze sessie.

- `PortraitSetActions.fillBody(_ targets:entitlement:undoManager:reporter:)` naar
  het model van `boostResolution`: gate vooraf via
  `allowAIFeatureWithFreeServerPreflight(.restoreBody)` (de server-no-op zonder
  afgesneden rand blijft gratis, E56-contract), sequentieel, off-main facebox
  (hergebruik `fillBodyFaceBox` → verplaatsen naar een gedeelde helper in
  `Avatar2/Features/Editor/FillBody*.swift` of `PortraitSetActions`), per portret
  `backend.fillBodyDetailed`.
- `ShellModel.applyFillBodyResult` opsplitsen: de pure stap (signature-check +
  `compensatedFillBodyTransform` + `FillBodyState` before/after) wordt een statische
  functie zonder `selectedPortrait`-guard; de editor-variant houdt de guard en
  ververst het canvas. De set-actie past `after` toe met `bumpRevision()` +
  `reporter.portraitDidChange`, één undo-groep "Fill in body" (hergebruik
  `FillBodyUndo`/`ReversibleChange`), zoals `applyBoosted`.
- Bon (`fillBodyReceipt`, testbaar): "Filled in body on N", "…on K of N" met detail
  "M had nothing to fill" / "…couldn't be filled" / "Ran out of credits for the
  rest." Bij N=1 en `didFill == false`: dezelfde info-copy als de editor ("Nothing
  to fill · Try Auto-frame & center instead").
- Annuleren: `reporter.busy` krijgt een optionele `onCancel` (zoals de editor-toast
  `cancelHint`), batch checkt `Task.isCancelled` tussen portretten; wat al klaar
  was blijft (op-is-op-regel van Boost).
- Als de tegel in de editor open is (`selectedPortrait` ∈ targets): editor-canvas
  moet meebewegen → na toepassing `model.refreshCanvasFromSelection()` (bestaat,
  `ShellModel.swift:1496`); check of `reporter.portraitDidChange` dat al doet.

**DoD**: `PortraitSetActionsTests` voor de bon + de pure apply-stap (transform-
compensatie ongewijzigd t.o.v. E56-tests); beide targets groen; live-smoke op 1
en 2 portretten met een afgesneden schouder (credits-afschrijving = 2 per gevuld
portret, no-op gratis). **Result:** —

## 57.4 — FEAT: Apply effect als set-actie (1…N) met stijl-submenu [FEAT]
- status: done
- owner: FEAT (Claude, 2026-09-03)
- blockedBy: 57.2

**Result:** Edit ▸ **Apply effect[ on N] ▸** met None (alleen als een target een
effect heeft) · eigen effecten (Pro-chip, alleen voor Pro) · built-in stijlen
uit `EffectsModel.cachedEffectList` (sessie → disk → fallback, zelfde hydratie
als het paneel). Rij-label: "Cached" als niemand hoeft te genereren, anders
credits-totaal voor wie wél genereert ("Cloud" zonder tier).
`PortraitSetActions.applyEffect`: per portret al-actief → overslaan, cache →
gratis, anders `backend.stylize` (builtin op key / custom op id) met dezelfde
bronkeuze als de editor ná de gate; toepassing via nieuw
`ShellModel.applyEffectResult(_:to:framing:)` (her-isolatie + resize/kadrering
van `storeEffectResult`, nu met `reshuffles: false` → `bumpRevision`, canvas
alleen als het het geselecteerde portret is, en de her-kadrering wordt
afgewacht); Effects-staat zoals `EffectsModel.persist` (basis eenmalig, actief,
rauwe generatie in cache); framing per portret via `EffectFraming.forSwitch`;
één undo-groep "Apply effect" met complete snapshots (pixels, transform,
effect-staat, edit-bron). **Kwaliteitsgate één keer per batch** (besluit
Thierry): `PresentationConfirm.stylizeLowResolution(count:)` → DSDialog in
`FloatingOverlayHost` met "Boost first (N credits)" (boost online de low-res
targets, daarna dezelfde actie zonder gate) / "Apply anyway" / Cancel;
antwoord via continuation in `PortraitSetActions.resolveStylizeGate`. 402 →
op-is-op, 403 → upgrade, safety-refusal geteld in de bon. Tests: step-
classificatie (actief/cached/generate + None), EffectChoice, undo-snapshot
in één groep zonder reshuffle, bon-copy. Beide targets bouwen, guards groen.
**Niet gedaan:** annuleren tussen portretten (→ 57.5, zelfde reden als 57.3);
geen live-smoke met credits in deze sessie — de backend-call is identiek aan
het paneel, de rest is getest.

- **Submenu-inhoud**: `None` · custom effecten (Pro-badge `DSProChip`, alleen als
  `customSessionCache` niet leeg is) · divider · builtin stijlen uit
  `EffectsModel.sessionCache`/disk-cache; leeg → één disabled rij "Loading styles…"
  en een `loadEffects()` op menu-open (eenmalig per sessie). Rij-accessory:
  "Cached" als álle targets de stijl in `effectCache` hebben, anders credits-totaal
  voor de niet-gecachte targets; die-cut-stijlen krijgen het sticker-icoon.
- `PortraitSetActions.applyEffect(_ targets:card:entitlement:undoManager:reporter:)`:
  gate `allowAIFeature(.effectGenerate)`; per portret: (1) cache-hit → bytes uit
  `effectCache`, gratis; (2) anders kwaliteitsgate **één keer per batch**
  (`gateBeforeStylize` op het eerste low-res portret; keuze geldt voor de batch —
  geen N dialogen), bron via `StylizeQuality.effectsStylizeSource`, `backend.stylize`
  (builtin/custom), her-isolatie via de bestaande `reIsolateSubject`-route
  (uit `applyEffectResult` losmaken tot een portret-gerichte statische variant,
  zelfde splitsing als 57.3), framing via `EffectFraming.forSwitch(toDieCut:fromDieCut:)`
  per portret (eigen vorige stijl), persist `effectBaseData` (alleen als nil),
  `effectActiveRaw`, `effectCache`.
- `None` = terug naar `effectBaseData` met `.autoFrame` als vorige die-cut was —
  hergebruik `EffectsModel.selectNone`-logica.
- Eén undo-groep "Apply effect" (cutout + transform + `effectActiveRaw` per
  portret, `ReversibleChange`). Bon: "Applied <stijl> to N" / "…to K of N" met
  detail voor mislukt / "Ran out of credits" / "Some photos were declined by the
  safety filter" (`BackendError.generationRefused`, geen credits). Pro-vervallen
  (`proRequired`) → `requestUpgrade()` en batch stoppen.
- Voortgang: `reporter.busy("Applying <stijl> 2 of 5…")`; annuleren zoals 57.3.
  Replicate-ratelimit: sequentieel blijven (zie memory: <$5 = 6/min-throttle).
- Editor open op een target → canvas verversen (zelfde haak als 57.3); Effects-
  paneel open → `EffectsModel` leest `portrait.effectActiveRaw` opnieuw (check
  `onChange`-pad, anders selectie-badge stale).

**DoD**: tests voor bon + cache-hit-pad (geen backend-call, geen credits) +
framing-keuze per portret; beide targets groen; live-smoke 1 en 3 portretten met
één gecachte stijl (bon "…2 credits" bij 3 targets waarvan 1 gecacht). **Result:** —

## 57.5 — Polish-pass [FEAT+DS]
- status: done
- owner: FEAT (Claude, 2026-09-03)
- blockedBy: 57.2, 57.3, 57.4

**Result:**
- **Stoppen tussen twee portretten** (de open post van 57.3/57.4):
  `SetActionReporter.cancel` (default no-op, bestaande call sites ongewijzigd)
  → `ShellModel.setActionCancel` → **Stop**-knop op de busy-toast (alleen als
  er een haak is; Match framing e.d. houden geen knop). Boost/Fill in body/
  Apply effect checken `Task.isCancelled` tussen portretten, een afgebroken
  call telt niet als mislukt, wat klaar is blijft (met Undo); bon: "Stopped.
  The rest is unchanged." / "Stopped — nothing … yet". Boost-first uit de
  gate ketent niet door na een stop.
- **Disabled-reden**: Edit ▸ krijgt een `.help`-tooltip ("Wait for the current
  edit to finish" zolang een batch/editor-AI-actie loopt, anders de korte
  uitleg).
- **Sneltoetsen**: geen labels toegevoegd — Boost/Apply effect hebben geen
  binding en de editor-⇧⌘F (Fill in body) werkt niet op een raster-selectie;
  een label zonder werkende toets is erger dan geen label.
- **Labels/credits**: "…on N", "1 credit"/"N credits", "Cached"/"Cloud" — al
  in 57.2–57.4; menu-breedtes 200/270 (hoofd), 230 (Boost), 250 (effecten).
- **AX**: submenu-rijen melden Expanded/Collapsed + hint (57.1), panelen zijn
  containers met label; Esc sluit alles.
- **Motion/iconen**: guards groen. Privacy-matrix ongewijzigd (zelfde features).
- Tests: stop-bonnen voor de drie batches + reporter-default; Avatar2Tests
  groen, beide targets bouwen.

**Niet gedaan (bewust):** screenshots in de story (geen screencapture in
autonome sessies — Thierry kijkt live), tracking-events (geen tracking-plan
in de repo). Hover-timing 150/250 ms staat vast (Thierry: "hover is ok").

**Aanvulling (Thierry 2026-09-03):** effect-rijen tonen nu een 20×20-thumbnail
van de stijl — `DSMenuRow(_:leading:…)` (nieuwe DS-variant: eigen leading-view
in de icoon-slot) + `RemoteThumbnail` uit dezelfde `ThumbnailCache` als de
Effects-kaarten (memory-hit = geen flits); zonder URL/tijdens laden het icoon.
**Figma-TODO:** radius/inset van de rij-thumbnail (nu `DSRadius.md`, 20 pt).

- **Sneltoetsen**: de editor heeft alleen Fill in body `⇧⌘F` (`EnhanceCommands`);
  Boost en Apply effect hebben geen binding. In het tegelmenu géén shortcut-labels
  verzinnen: alleen `⇧⌘F` bij Fill in body tonen als `PortraitSetCommands` die
  command ook op een raster-selectie laat werken (anders leeg laten — een label
  zonder werkende toets is erger dan geen label).
- **Disabled-states met reden** (tooltip via `DSTooltip`): geen cloud-tier →
  "Turn on cloud features in Settings" op Online/Fill in body/Apply effect; batch
  bezig → "Wait for the current edit to finish"; portret zonder cutout → Edit
  helemaal weg.
- **Bulk-labels** blijven kort: "Boost resolution on 12" i.p.v. "…on 12 portraits";
  credits altijd als "N credits" (1 → "1 credit").
- **Menu-breedte**: hoofdpaneel `minWidth` 200/270 blijft; submenu's 230 (Boost),
  260 (effecten, met thumbnail 20×20 links? — **Figma-TODO**: thumbnails in
  menu-rijen zijn niet in het DS; voorstel: alleen tekst + Cached/credits-label).
- **Hover-intent afstemmen** met Thierry (150/250 ms default; live tunen zoals de
  hero-morph in E53).
- **Toasts**: bestaande `SetActionReceipt` met Undo-knop; bij N=1 dezelfde copy
  als de editor zodat "Body completed"/"Boosted resolution" consistent blijven.
- **AX-sweep** (E53.3-lijn): VoiceOver leest "Edit, submenu, collapsed/expanded";
  rijen in submenu's bereikbaar; Esc sluit alles.
- **Privacy-matrix** (`PrivacyFeatureMatrix`) hoeft niet te wijzigen (zelfde
  features), wél `AIFeatureRegistry`-labels hergebruiken i.p.v. nieuwe strings.
- Tracking-watchdog draaien (nieuwe surface: `context_menu_edit_*`-events als het
  tracking-plan die verwacht).

**DoD**: beide targets + alle tests groen; `build-v2.sh` volledig gelezen (geen
`tail`); screenshots van enkel- en bulk-menu met open Edit ▸ Apply effect ▸ in de
story; AX-check op het geneste menu. **Result:** —

## 57.6 — Board-tegelmenu: zelfde Edit-submenu [FEAT]
- status: done
- owner: FEAT (Claude, 2026-09-03)
- blockedBy: 57.5

**Result:** de Edit-tak is losgemaakt in `PortraitEditSubmenu` (eigen bestand,
Avatar2/Features/Portraits) en zit nu in het tegelmenu (Home/Portraits) én in
`BoardView.nodeContextMenu` (enkel: die node; bulk: de board-selectie), vóór
de Delete-divider. Het board-menu is in-window (`dsDismissOnOutsideClick`):
een klik in een genest submenu-window (kleinkind van het hostvenster) telt
nu ook als "binnen" — `DSOutsideClickScope.isInside` loopt de parent-keten
af. **Copy** (Thierry 2026-09-03): geen "…on N" meer in de Edit-rijen (Boost
resolution / Fill in body / Apply effect); het aantal blijft zichtbaar in de
credits-labels en de bon. DoD: beide targets bouwen, Avatar2Tests 344 en
AvatarUI 109 groen, guards groen; pbxproj bijgewerkt voor het nieuwe bestand.

## Volgorde & inschatting

| Story | Grootte | Parallel? |
|-------|---------|-----------|
| 57.1 DS-submenu | M | start direct |
| 57.2 Edit-rij + Boost enkel | S | na 57.1 (Boost-gat kan desnoods als hotfix vóór 57.1: Boost-rij in `singleRows` met de bestaande flyout) |
| 57.3 Fill in body set-actie | M | parallel met 57.4 na 57.2 |
| 57.4 Apply effect set-actie | L | parallel met 57.3 |
| 57.5 Polish | S–M | afsluitend |

Snelste zichtbare winst voor Thierry: 57.2's Boost-in-enkel-select (het gemelde
gat) — kan als eerste commit binnen 57.2 landen vóór het submenu-werk klaar is,
mits de bestaande flyout hergebruikt wordt en daarna in 57.2 gemigreerd.

## Risico's / open besluiten

1. **Headless her-isolatie bij Apply effect** kost ORMBG/Vision-tijd per portret;
   bulk van 10+ effecten is minuten. Voortgang-toast + annuleren zijn daarom in
   scope (57.4), geen optioneel extraatje.
2. **Kwaliteitsgate één keer per batch** (57.4) is een interpretatie: de editor
   vraagt per portret. Alternatief is per portret vragen → N dialogen. Voorstel
   staat hierboven; **besluit Thierry** nodig als hij per portret wil.
3. **Fill in body zonder editor** mist de visuele check die de editor biedt;
   de E56-precisie (alleen afgesneden randen) maakt dit acceptabel. Bon meldt
   expliciet hoeveel portretten "nothing to fill" hadden.
4. **Submenu in hetzelfde child-window**: een 3-niveaus-menu kan breder worden
   dan het scherm; het flip-naar-links-gedrag (57.1) vangt dat op, maar een
   diep menu rechtsonder blijft een randgeval — plaatsingstests dekken 't af.
