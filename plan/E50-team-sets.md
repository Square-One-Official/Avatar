# E50 — Team-sets verdiepen

Team: **FEAT**

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, Shell-review F3/F6).
Backlog-epic: het huidige set-concept (platte mappen, board-lens per map) is
functioneel maar dun t.o.v. de productbelofte "one look for every **team**
portrait" — er zijn geen set-brede acties, en Home behandelt mappen niet. Vult aan
op de directe naming-fixes in `E36-home-gallery-ia.md` (36.5/36.6).

---

## 50.1 — Map-brede acties + ⌘A per lens
- status: done
- team: FEAT
- blockedBy: —
- note: gepromoveerd backlog → ready 2026-07-02, akkoord Thierry (alle epics afwerken)

**Wat:** set-brede acties (Align/Match lighting/bulk-export) werken vandaag alleen
op een handmatige multi-selectie; er is geen "hele map selecteren". ⌘A bestaat
alleen in de board-lens (`BoardView.swift:703`), niet in grid/list/gallery.
**Voorstel:** contextmenu op de map-rij uitbreiden met "Select all in folder" /
"Align set" / "Match lighting" / "Export set"; ⌘A registreren in elke lens op de
huidige selectie-scope.
**DoD:** vanuit elke lens is een hele map in één actie te selecteren en te
bewerken; tests groen; Result-regel.
**Result (2026-07-02):** map-rij-contextmenu in de left-nav heeft nu Select all
in folder / Align set / Match lighting / Export set (zelfde `PortraitSetActions`
als de handmatige multi-selectie, maar op de hele map; Match-referentie = het
jongst bewerkte portret, disabled bij <2). Nieuwe pure helper `FolderSetScope`
(map-filter + lens-volgorde) deelt de scope-logica; `ShellModel.
selectAllPortraits` zet selectie + ⇧-anker. ⌘A geregistreerd in
`PortraitsGalleryView` voor grid/list/gallery op de zichtbare scope (board hield
z'n eigen ⌘A — bewust uitgesloten tegen dubbele registratie). 5 nieuwe tests
(`FolderSetScopeTests`); beide targets bouwen, Avatar2- + AvatarKit- +
AvatarUI-suites groen.

## 50.2 — Home met echte recent-secties
- status: backlog
- team: FEAT
- blockedBy: —

**Wat:** `HomeView.swift:78-101` toont `featured(portraits.first)` als 1 grote kaart
+ "Earlier" = `dropFirst()` — geen tijdsgroepering. Sort is `updatedAt`, dus een
achtergrond-tweak op een oud portret katapulteert het naar de hero-kaart en
verschuift het hele rooster.
**Voorstel:** featured-rij van de laatste 3-4 items, of echte datum-secties
(Today/This week/Earlier) i.p.v. 1-vs-rest.
**DoD:** Home toont een stabiele, begrijpelijke recent-indeling die niet
herschudt bij elke kleine edit; tests groen; Result-regel.

## 50.3 — Match lighting non-destructief + stabiele rasterorde + toast met Undo
- status: done
- team: FEAT (+DS: DSToast-actieslot, akkoord Thierry 2026-09-02; +AI/INFRA: `SetLightingNormalizer`-uitbreiding)
- blockedBy: —
- note: uit Thierry's UX-review 2026-09-02 (screenshots Portraits-grid): tegels
  wisselen van plek na Match lighting, geen terugweg per portret, Adjust-sliders
  tonen niets, referentie is "de aangeklikte tegel". Plan: `~/.claude/plans/when-selecting-multiple-and-pure-brook.md`.

**Wat:** (1) elk raster sorteert op `updatedAt` en set-brede acties `touch()`-en
per portret → de selectie herschudt (de referentie blijft juist staan). (2) Match
lighting bakte de correctie in `cutoutData`; de enige terugweg was een onzichtbare
⌘Z (geheugen-only, 20 stappen met volle PNG's). (3) Adjust toonde niets. (4)
Referentie = aangeklikte/jongste/eerste — geen patroonherkenning.
**Voorstel:** `Portrait2.revision` als cache-token (`touch()` bumpt beide,
`bumpRevision()` alleen het token) — set-brede acties en hun undo/redo herschudden
niet meer. Match lighting schrijft de **Adjust-laag** (brightness/contrast/
temperature via `SetLightingNormalizer.adjustSuggestion` + `refine`; saturation
blijft) i.p.v. pixels: sliders tonen het resultaat, Reset draait 'm terug, undo
houdt geen PNG's meer vast. Doelkeuze `chooseTarget`: meerderheidscluster
(mediaan) of anders het best belichte portret; "Match lighting to this one" als
expliciete override; "Reset adjustments" in tegel-/Edit-menu; "Use folder
background" in het tegel-menu (map-default alsnog toepassen, aanvulling Thierry
2026-09-02). `DSToast` krijgt een actie-slot → "Matched 2 portraits to Joline ·
Undo". Board-duplicaat verwijderd, `CutoutDataUndo` weg.
**DoD:** raster blijft op z'n plek na Match framing/lighting/Set background én na
undo; Adjust-sliders tonen de match; per-portret terug via Reset; toast met Undo;
beide targets bouwen + tests groen; Result-regel.
**Niet in scope (follow-ups):** saturation/tint in het belichtingsmodel; overige
undo-appliers (ImageEnhance/FillBody) naar `bumpRevision`; samenvoegen van de
twee toast-slots (ShellView vs Avatar2App); WorkingToastView op het DSToast-
actieslot; al-gebakken portretten van vóór deze story zijn niet terug te draaien.
**Result (concept, 2026-09-02 — merge naar v2-main pending):** `Portrait2.revision`
+ `bumpRevision()`; alle 5 cache-/refresh-keys op revision; set-brede acties +
TransformUndo/board-batch-Adjust bumpen alleen revision. `SetLightingNormalizer`:
`adjustSuggestion`/`refine` (3 passes, brightness+contrast+temperature; CI-sign
empirisch geverifieerd) + `chooseTarget` (meerderheidscluster → mediaan, anders
best belicht, `preferred` als tie-break). `PortraitSetActions` herschreven:
off-main meten, Adjust-laag schrijven via `AdjustUndo`, `SetActionReporter`/
`SetActionReceipt` (busy → bon, Undo alleen als de groep nog bovenop ligt),
`resetAdjust`, `useFolderBackground`, `applyBackgrounds`. Menu's: "Match lighting"
(auto) + "Match lighting to this one" + "Reset adjustments (on N)" + "Use folder
background (on N)"; Edit-menu "Reset Adjustments on Selection". `DSToast(action:)`
+ `DSToastAction`. ShellModel `setActionToast` (.busy/.done) + reporter; ShellView
toont de bon met Undo (8 s). Board: eigen matchLighting weg, `CutoutDataUndo`
verwijderd. AdjustPanel volgt externe Adjust-wijzigingen. Tests: +21 AvatarKit
(normalizer), +15 Avatar2 (`PortraitSetActionsTests`), +3 AvatarUI (`DSToastTests`);
Avatar2 268/268, AvatarKit + AvatarUI groen, Avatar (v1) én Avatar2 bouwen.
Review-ronde Thierry 2026-09-02 (screenshots "they do not match" / "oversaturated,
contrast rich on one side"): diagnose op de echte OPP-cutouts (env-gated
`SetLightingDiagnosticsTests`) toonde dat de refine-lus naar de klemwaarden wegliep
en CIColorControls-brightness (additief, lineair) zwart mee optilde. Fix: brightness
in `PortraitEnhancer.colorAdjust` is nu een belichting (CIExposureAdjust, ±1 EV
over de slider), de suggestie lost gain+contrast exact op in lineair licht,
contrast-range smal (0.85…1.15), geen iteratie op kelvin/spreiding; kwaliteitsbanden
verruimd zodat studiolicht (Joline) de referentie wordt. Grens van de aanpak:
lichtRICHTING (zijlicht) en clippende highlights (witte shirts) kan een globale
slider-match niet oplossen — echte relighting = AI-model, aparte story.
Rasterorde: de change-history van de store bewijst dat de batch alleen
adjust+revision schrijft; de verschuiving in de screenshots kwam van een oude-build
Match framing (14:14, touch op alle targets).
**Aanvulling Thierry 2026-09-02 ("als je via folder meerdere selecteert, mag
Boost als optie komen bij rechtermuisknop"):** bulk-tegelmenu krijgt "Boost
resolution on N" met flyout On device (Free) / Online (Best · 3 credits per
portret, totaal in het label). `PortraitSetActions.boostResolution` — sequentieel
off-main (`LocalUpscale` of `backend.upscale(.high)`), gate vooraf via
`allowAIFeature(.boostOnline)`, toepassing in één undo-groep "Boost Resolution"
(`applyBoosted`: cutoutData + schaal-bijstelling + `cutoutDerivesFromOriginal`
= false, `bumpRevision` → raster blijft staan), bon met Undo; op-is-op stopt de
batch en meldt wat wél gelukt is. Tests: `PortraitSetActionsTests` (+4).
Let op: `scripts/check-icon-sizes.sh` faalt op twee regels in de VREEMDE WIP
(`PrivacyTierRadioGroup.swift:41`, `AdjustPanel.swift:390`) — niet uit deze story.
**Besluit Thierry 2026-09-02: Match lighting GESCHRAPT** — "not good enough yet,
we might do it AI-powered later". Entry points (tegel-/Edit-/map-menu, board-
toolbar, `--board-match-light`) achter `AppFeatureFlags.matchLightingEnabled`
(uit; DEBUG `--enable-match-lighting`); "Reset adjustments" (tegel-/Edit-menu)
gaat mee achter die flag. Code + tests + diagnose-test blijven.
Brightness-slider terug op het uitgeleverde (additieve) CIColorControls-gedrag.
Wat WEL landt: stabiele rasterorde (revision), toast met Undo, Use folder
background, Match framing/Set background zonder herschudden, Board-
unificatie, `CutoutDataUndo` weg. Vervolg: 50.4.

## 50.4 — AI-powered Match lighting (relighting)
- status: backlog
- team: AI+FEAT+INFRA
- blockedBy: —

**Wat:** een globale slider-match (E50.3) kan lichtRICHTING (zijlicht) en
clippende highlights (witte shirts) niet matchen; de set oogt daarna niet als
"dezelfde studio". Echte matching = relighting per portret naar een referentie-
look (cloud-model, credit-kostend), met `SetLightingNormalizer.chooseTarget` /
`referenceStats` voor de referentiekeuze en de E50.3-toast/undo-infra eromheen.
**DoD:** bakeoff van een relight-model op de OPP-set (Joline als referentie),
go/no-go Thierry; daarna feature achter dezelfde flag.
**Aanvulling 2026-09-02 (review Thierry, screenshots Portraits-grid):** het
tegel-contextmenu viel ónder de "Framing already matches"-toast en werd aan de
onderrand van het venster afgekapt. Beide zaten in de vaste `.overlay`-volgorde
van ShellView. Nieuw: `DSFloatingWindow` (AvatarUI) — DS-menu's én toasts leven
in een borderless, niet-activerende NSPanel als child window van het app-venster.
Regels: (1) een menu klemt op het schérm, niet op het venster (mag eroverheen,
zoals een native NSMenu; échte maat gemeten i.p.v. de 220×260-schatting);
(2) wat het laatst verschijnt staat bovenop — toast ná menu → toast boven,
menu ná toast → menu boven (`bringToFront` ordent boven de andere DS-panels van
hetzelfde venster); (3) menu sluit op klik buiten (ook buiten de app), Esc,
app-deactivatie en venster-move/resize; toast volgt het venster en wordt op het
venster geknipt zodat de slide-in/out gelijk oogt aan de oude transition (reduce
motion → fade). `DSContextMenuOverlay` houdt z'n signature (scrim blijft
in-window); `menuWidth`/`menuHeight` sturen niets meer. ShellView-toast via
`DSFloatingWindowAnchor` (los van `body` — type-check-limiet), Avatar2App-toast
via `.dsFloatingToast`. `DSMotion.Duration` + `easeOutControlPoints` gedeeld met
AppKit. Tests: +7 AvatarUI (`DSFloatingLayoutTests`, puur) en 2 env-gated
venster-tests (`DS_FLOATING_WINDOW_TESTS=1`, `DSFloatingWindowRuntimeTests`:
menu steekt onder de vensterrand uit; z-volgorde toast↔menu).

## 50.5 — Map dupliceren mét inhoud
- status: done
- team: FEAT
- blockedBy: —
- note: verzoek Thierry 2026-09-03 — "een effect op alle mensen toepassen, maar
  niet bij het origineel"

**Wat:** een set-brede actie (effect, achtergrond, framing) werkte altijd op de
bronmap zelf; er was geen manier om een variant van het hele team te maken
zonder het origineel te raken.
**Voorstel:** "Duplicate" in het map-contextmenu (left-nav, tussen Rename en
Delete — zelfde plek als bij banners): kopieert de map + alle portretten en
opent de kopie.
**DoD:** map-kopie met identieke portretten (pixels, achtergrond, Adjust, frame,
effect-cache) en de map-default-achtergrond; origineel onaangeraakt; één
undo-stap; tests groen; Result-regel.
**Result (2026-09-03):** `FolderDuplicator` (Portraits) + `Portrait2.duplicate()`
(diepe kopie; `lastOpenedAt`/`v1ImportID`/board-positie bewust niet mee —
de board-lens van de kopie doet z'n eigen layout). Kopienaam Finder-stijl
("Team copy", "Team copy 2", …). Kopieën krijgen oplopende `updatedAt`-stempels
vanaf nu → bovenaan in elke lens, onderlinge volgorde van de bron intact. Eén
undo-groep "Duplicate Folder" (undo wist kopie + portretten en zet de lens terug
op de bron; redo dupliceert opnieuw), gemeld via de compacte set-action-pill met
Undo. Dupliceren is géén import: de Starter-cap (server-side cutout-claims)
wordt niet geraakt — bewust niet gegated. 4 nieuwe tests
(`FolderDuplicatorTests`).
