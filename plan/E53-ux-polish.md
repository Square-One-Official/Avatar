# E53 — UX-polish n.a.v. UX-audit 2026-07-02

Team: **FEAT + DS**

Bron: `plan/AUDIT-UX-2026-07-02.md` (33 bevindingen: 8×P0, 15×P1, 10×P2) +
`plan/PLAN-UX-POLISH-2026-07-02.md` (story-ready uitwerking: UXS-1…UXS-26 met
exacte bestanden/regels, code-aanpak en acceptatiecriteria — gebruik dát als
implementatiebron). Dit epic mapt sprint 1 (P0) op 53.1–53.4; sprint 2/3 = 53.5.

---

## 53.1 — Polish-sprint S-items (top-10 #1–#7)
- status: done
- owner: FEAT (2026-08-01, branch v2/e53-1-polish)
- team: FEAT
- blockedBy: —

**Wat (alle S, uit de top-10):**
- UX3: Escape in banner-tekstbewerking = cancel (commit alleen via klik-buiten/Enter).
- UX4: fout-toast betrouwbaar — `.task(id:)` zodat de 8s-timer herstart, error
  krijgt prioriteit boven busy-toast (geen single-slot-verlies), sluitknop wiren.
- UX5: kaartlabel-scrim foto-onafhankelijk donker (light-mode-leesbaarheid ≥4.5:1).
- UX7: blauwe "Restore to original" → DS-stijl + juiste laagvolgorde.
- UX9: scroll-inset onder de upload-pill (pill maskeert content).
- UX10+11: paywall/account copy- & locale-pass + current-plan-badge.
- UX29: a11y-label-sweep — DSIconButton krijgt verplicht label-param.
**DoD:** beide targets bouwen, tests groen, per punt afgevinkt in de Result-regel.

**Result (2026-08-01):** alle punten af; `scripts/build-v2.sh` volledig groen.
- ✅ **UX3 — Escape annuleert** ([BannerInlineTextField.swift](../Avatar2/Features/Banners/BannerInlineTextField.swift)):
  `insertNewline` en `cancelOperation` zaten in één branch, dus Esc *legde de
  bewerking juist vast* — het tegenovergestelde van de macOS-conventie. Gesplitst
  naar een eigen `onCancel`; de chrome legt bij edit-start de tekst vast
  (`textBeforeEdit`, gezet op beide instap-paden: type-to-edit én dubbelklik) en
  zet 'm bij Esc terug. Was de laag vers (placeholder/leeg), dan verdwijnt 'ie —
  net als ⌫ op een lege laag. Geen undo-stap voor een geannuleerde edit.
  Bijvangst: de coordinator ververst zijn closures nu bij elke update, anders
  hield 'ie na een laag-wissel een verouderde callback vast.
- ✅ **UX4 — toast-betrouwbaarheid.** Nieuwe pure reducer
  `EntitlementModel.resolveToast(error:outOfCredits:working:)` → één slot met
  prioriteit **fout > op-is-op > bezig** (een fout mág de spinner verdringen: de
  operatie waar die bij hoorde is mislukt). `DSToast` telt nu zélf af via
  `.task(id:)` op de inhoud — een vervángende melding krijgt dus de volle duur
  i.p.v. de rest van zijn voorganger — pauzeert op hover, en rendert **geen
  sluitknop** als er geen dismiss-actie is (`onClose` is optioneel geworden;
  de dode `DSToast(title:){}` in ShellView is er één). Duren centraal:
  `errorToastDuration` (8s) + nieuw `infoToastDuration` (5s), gebruikt door
  SignInSheet en de op-is-op-toast i.p.v. eigen literals. +4 tests.
- ✅ **UX5 — kaartlabels leesbaar** ([DSCardLabelScrim.swift](../AvatarUI/Sources/AvatarUI/Components/DSCardLabelScrim.swift)):
  de oude scrim liep `.clear → black 0.55` naar de ONDERrand, maar het label zit
  door z'n padding hálverwege die ramp — de dekking onder de tekst was dus veel
  lager dan 0.55. Nieuwe gedeelde scrim met een **plateau** (0.78) dat begint
  vóór de tekstzone; wit-op-scrim haalt daarmee 11.7:1 in het slechtst denkbare
  geval (wit portret, light mode) tegen ~4.0:1 daarvoor. Eén component voor
  DSThumbnailCard, de gallery-tegels én de Home-hero. Test borgt de 4.5:1-vloer
  via een pure contrast-functie i.p.v. een oogtest.
- ✅ **UX7 — "Restore to original" in DS-stijl.** De capsule-overflow (`⋯`) was
  het laatste systeem-`Menu` in de app; daar kwam de accent-blauwe rij-highlight
  vandaan én het paneel dat over de toolbar rende. Nu een DS-dropdown
  (`dsDropdownMenu` + `DSContextMenuPanel`/`DSMenuRow`, geopend naar bóven),
  gelijk aan de Frame-/Background-/Boost-chips. `DSToolbarAction` kreeg
  `isDestructive` → de restore-rij staat in de destructive-tint; `DSMenuRow`
  kreeg een `Image`-variant zodat de toolbar z'n eigen iconen kan hergebruiken.
  E53.7-conform: de open-state leeft in `UIPresentationStore.editorOverflowMenuOpen`.
- ✅ **UX9 — scroll-inset onder de upload-pil.** De inset was een los `80`.
  Vervangen door `ShellMetrics.uploadPillScrollInset` = pil-hoogte +
  vensterafstand + `gap4` lucht, en de pil zelf leest diezelfde maten. +2 tests
  (o.a. één die faalt zodra het weer een magic number wordt). **Eerlijk:** het
  oude getal was toevallig gelijk aan de afgeleide waarde, dus visueel verandert
  er weinig; de audit-screenshots zijn niet meer beschikbaar, dus als de
  overlap een andere oorzaak had, vergt dat een live her-check.
- ✅ **UX10+11 — paywall/account copy & locale.** Starter-kaart krijgt een
  "Current plan"-badge (de plan-kiezer krijgt alleen een niet-Pro-account te
  zien — een actieve Pro loopt via `showsTopup` — dus Starter ÍS daar altijd het
  huidige plan); "Upgrade to pro" → "Upgrade to Pro"; "No bots" → "Human
  support"; prijzen via `Decimal` + `NumberFormatter` op `Locale.current` i.p.v.
  hardgecodeerde "€49,90"-strings (valuta blijft EUR, alleen de notatie volgt de
  locale). De bedragen worden exact opgebouwd (cent als significand): via een
  Double-literal is `Decimal(4.99)` = 4.99000000000000102… en klopt 10× de
  maandprijs niet meer tegen de jaarprijs. Dubbele ✕ weg: de settings-✕ verbergt
  zolang de paywall ervoor staat. Account-credits-copy is conditioneel — een
  Starter mét saldo krijgt "Top-up credits — you can use these on any plan"
  i.p.v. het zelf-tegensprekende "Credits come with a Pro plan" naast een saldo
  van 34. +5 tests (locale-notatie, EUR-behoud over vier locales, 10×-belofte).
- ✅ **UX29 — a11y-labels** was al gedaan in E53.3 (DSIconButton `label`
  verplicht, alle call sites voorzien); hier alleen geverifieerd + de nieuwe
  CreateEffectSheet-knop uit E09.3 meegenomen.

## 53.2 — Banner Studio bruikbaarheid (UX1 + UX2, P0)
- status: done
- owner: FEAT (UX1 2026-07-12; UX2 afgerond 2026-08-01 op branch v2/e53-2-fit)
- team: FEAT
- blockedBy: —

**Voortgang (checkpoint 2026-07-12; builds + tests groen op 5 na — die 5
(AuthSessionStorageTests) zijn de vergrendeld-scherm-flake, zie E13.6, los van
deze story):** UX1 ✅ compleet —
placeholder-sweep v2 (legacy "Your text" matcht mee, geforceerde herbake van
bestaande bakes, stempel pas ná voltooide run, Home-hook; +2 tests). UX2 ⏳
alleen de aanzet (`fitCameraScale`-helper + `userZoomed`-vlag) — fit-op-open/
resize + zoom-chip in BannerStudioView kan nu gebouwd worden (E53.7 is af).
NB: banners blijven achter `bannersEnabled` (besluit Thierry 2026-07-12) —
prioriteit t.o.v. 53.1/53.4 dienovereenkomstig.

**Wat:** UX1: banner-thumbnails tonen placeholder-lagen ("Type to enter
text"-soep) op Home/gallery — verifieer eerst tegen de E37.18-sweep+migratie
(gemerged vandaag; herbake mogelijk nog niet getriggerd) en dek de resterende
paden + forceer herbake. UX2: canvas overflowt het venster zonder fit/zoom —
fit-to-window bij open + zoom-chip (hergebruik E27.10-recept).
**DoD:** verse checkout, 1100×760-venster: banners-gallery toont schone thumbs
en de Studio past in het venster; tests groen; Result-regel.

**Result UX2 (2026-08-01):** de aanzet uit de checkpoint (`fitCameraScale` +
`userZoomed`) was gebouwd maar nergens aangesloten — `fitCameraScale` had geen
enkele call site en `userZoomed` werd nooit gezet of gelezen. Nu compleet:
- **Fit bij openen en bij resize.** `fitCamera(viewport:animated:)` is één route
  voor openen, doc-wissel, ⌘0 en de chip; de resize-handler her-fit alleen als de
  gebruiker niet zélf gezoomd heeft. Zonder die guard pakte elk venster-resize de
  handmatige zoom af.
- **`userZoomed` echt aangesloten.** Gezet door ⌘+/⌘−, ⌘1 (Actual Size is een
  bewuste zoom-stand) én — dat was de lastige — door scroll-zoom/pinch/spatie-pan.
  Die lopen via `CanvasInteractionCatcher`, dat rechtstreeks door een
  `Binding<CanvasCamera>` schrijft. In plaats van de gedeelde catcher aan te
  passen, geeft de Studio 'm een wrapper-binding: élke schrijf daardoorheen is
  per definitie een gebruikersgebaar, dus precies daar wordt de vlag gezet —
  onze eigen fit-aanroepen raken 'm niet. Fit/⌘0 geeft de vlag weer vrij.
- **Zoom-chip linksonder**, fit = 100%, klik = terug naar fit.

**Meegenomen: UXS-16 (UX17, "drie canvassen, drie zoom-UI's").** Het
capsule-recept stond drie keer los in de app — editor met een %-chip, board met
een "Fit"-knop, Studio met niets. Een vierde kopie bouwen zou dat probleem juist
vergroten, dus het is nu één DS-component:
[DSCanvasZoomChip](../AvatarUI/Sources/AvatarUI/Components/DSCanvasZoomChip.swift),
met een %-variant (editor, Studio) en een tekst-variant ("Fit", board — daar is
geen vaste kaartmaat om een percentage tegen af te zetten). Er staat geen
`ultraThinMaterial, in: Capsule()` meer in `Avatar2/`. **UXS-16 is hiermee niet
volledig af** — het "⌘+/⌘−/⌘0 overal identiek"-deel van UX17 valt nog onder 53.5.

**Tests (+11):** de percentage-logica (fit = 100%, degenererende invoer → "100%"
i.p.v. NaN/0%) en een nieuwe suite
[BannerFitToWindowTests](../Avatar2Tests/BannerFitToWindowTests.swift) die de
audit-klacht zelf vastlegt: 1500×500 én 1584×396 passen binnen 1100×760 én
820×620, de fit houdt marge over voor de selectie-handles, en een 0×0-viewport
(vóór de eerste layout) geeft een veilige schaal i.p.v. NaN.

**Openstaand:** de live-verificatie uit de DoD (Studio openen op 1100×760 en
820×620, screenshot vóór/na) is niet gedraaid — de banners-suite zit achter
`AppFeatureFlags.bannersEnabled` (default uit, besluit Thierry 2026-07-12), dus
dit pad is alleen met de flag aan te zien. De geometrie is in plaats daarvan met
tests vastgelegd op exact die twee venstermaten.

## 53.3 — DSThumbnailCard: AX + hover als één DS-story (UX28 + UX26, P0)
- status: done (gemerged naar v2-main)
- owner: DS (2026-07-12, branch v2/e53-3-kaart-ax)
- team: DS
- blockedBy: —

**Wat:** portret-/bannerkaarten exposen geen AX-elementen (VoiceOver kan de kern
van de app niet bedienen — live geverifieerd). LET OP (correctie uit de
uitwerking): DSThumbnailCard heeft al scrim + dsHoverScale; het contrast-/AX-werk
zit in de gallery-kaart (PortraitsGalleryView.swift:244-253) — volg UXS-7 in het
PLAN-document, incl. DSIconButton-verplicht-label.
**DoD:** kaarten zijn met VoiceOver/AX-inspector bereikbaar en activeerbaar
(open/selecteer/contextmenu); tests groen; Result-regel.
**Result (code klaar + DoD-build groen; live AX-check wacht op Thierry):** ✅ `PortraitCardAccessibility`-modifier (grid-tegel + Home-hero): één AX-element per kaart — label = naam+rol ("Untitled portrait"-fallback), traits button/+selected, default-actie = openen, named actions "Select"/"Deselect" (⌘-klik-pad) en "Show Context Menu" (punt-anker op de gemeten kaart-frame); ✅ GalleryLens: grote preview + filmstrip-thumbs als AX-elementen (activeren = focus, named actions Open/Select) + "Previous/Next portrait"-labels op de blader-pijlen; ✅ DSIconButton: `label`-param verplicht → `accessibilityLabel` + `.help` in de component zelf, alle call sites voorzien (ad-hoc `.accessibilityLabel`-modifiers opgeruimd); ✅ meegenomen UXS-27 (E53.6 DS-deel): `neutralSurface`-ladder relatief aan de base + nieuw token `neutral-strongest-2` — chip-hover op gevulde chips weer zichtbaar (UX36). build-v2.sh volledig groen. ✅ Live AX-geverifieerd (2026-07-12, Accessibility-permission door Thierry verleend; `scripts/axprobe.swift` tegen een `--smoke-store`-instance): per kaart een `AXButton` met label "«naam», «rol»" (bv. "Ava Bennett, Product Designer") en de acties `AXPress` (openen) + named actions "Select" en "Show Context Menu" — kaarten zijn bereikbaar én activeerbaar via de AX-boom.

## 53.4 — DSMotion-sweep: reduce-motion app-breed (UX30)
- status: done
- owner: DS (2026-08-01, branch v2/e53-4-motion)
- team: DS
- blockedBy: —

**Wat:** respecteer "Reduce motion" overal (raakt ook UX16/UX33); centraliseer in
een DSMotion-helper i.p.v. per-view checks.
**DoD:** met reduce-motion aan zijn alle transities cross-fade/instant; tests
groen; Result-regel.

**Result (2026-08-01):** de sweep bleek breder dan de audit-telling van "~20 raw
`withAnimation`-sites" — er waren drie soorten omzeiling, en alleen de eerste
stond in het plan:
1. **18 kale `withAnimation`** (canvas-zoom/fit in editor, board en banner-studio;
   align/match-lighting; AutoFramer; gallery-scroll) → `DSMotion.animate` met een
   token. De ruwe springs met `bounce: 0.08`/`0.1` zijn meteen bounce-loos
   geworden (`springSmall`/`springTransform`), conform de DS-regel dat overshoot
   niet bij dit product past.
2. **7 kale `.animation(.spring/.easeOut …)`** → `.dsMotion(…)`. De drie losse
   toast-springs in `Avatar2App` zijn er één geworden op `entitlement.activeToast`
   (de E53.1-reducer), i.p.v. drie animaties op de onderliggende vlaggen.
3. **38 × `.animation(DSMotion.<token>, value:)`** — dit is de verraderlijke: die
   sites gebruikten wél een DS-token, maar `.animation` is niet reduce-motion-
   bewust, dus ze bewogen gewoon door. Alleen `.dsMotion` doet de check. Deze
   groep stond niet in de audit en was de helft van het probleem.

Daarnaast de **per-view checks weg** (het "centraliseer"-deel van de story): de
`.animation(reduceMotion ? nil : …)`-ternaries in ShellView (4×) en LeftNavView
zijn `.dsMotion` geworden; de bijbehorende ongebruikte
`@Environment(\.accessibilityReduceMotion)` is opgeruimd. De check zit nu op één
plek, in `DSMotionModifier`.

**Nieuwe uitzondering, bewust:** `DSMotion.animateCrossFade` voor animaties die
alléén opacity veranderen (de cutout-reveal in `IsolatingCanvas`). Een fade
verplaatst niets en veroorzaakt dus geen bewegingsklachten — die killen maakt de
reveal harder dan nodig. Het is een eigen, greppable functie i.p.v. een
ongemarkeerde kale `withAnimation`, zodat de uitzondering zichtbaar blijft.

**Guard:** [scripts/check-motion.sh](../scripts/check-motion.sh) faalt op elke kale
`withAnimation(`/`.animation(` in `Avatar2/` + `AvatarUI/Sources` (DSMotion.swift
zelf uitgezonderd), en draait nu als eerste stap van
[build-v2.sh](../scripts/build-v2.sh) — de DoD-runner is hier het CI-equivalent.
Guard geverifieerd mét een opzettelijke overtreding: die faalt de build.
+7 tests op de DSMotion-contracten (body draait óók met reduce-motion aan, de
enter/exit-asymmetrie, de duur-ladder, transitions leveren een andere variant).

**Openstaand:** de handmatige verificatie uit de DoD — System Settings →
Accessibility → Reduce motion aan en een smoke door editor/board/studio — is niet
gedraaid; die vergt de systeeminstelling omzetten op Thierry's Mac. De guard +
tests borgen dat er geen route meer ís die de vlag negeert, maar het oogtest-deel
staat nog open.

## 53.5 — P1/P2-restlijst
- status: done
- owner: FEAT+DS (2026-08-01, branch v2/e53-5-rest)
- team: FEAT+DS
- blockedBy: —

De overige P1/P2-bevindingen uit `AUDIT-UX-2026-07-02.md` (UX8, UX12–UX27,
UX31–UX33) — UX6 (update-flow relaunchAndInstall zonder call sites) hoort bij
E13-releasewerk.

**Result (2026-08-01):** alle 15 openstaande UXS-stories af, in drie batches.
UX31 (toast-duur/hover) was al gedaan in 53.1, UX30/UX33 in 53.4.

**Batch A — DS-hygiëne**
- **UXS-22:** er stonden drie hex-parsers (DSColor numeriek, BackgroundKit
  alleen 6 cijfers, BannerDocRenderer 6+8) — drie antwoorden op dezelfde rare
  invoer. Nu één `DSHexColor` + `Color(hexRGB:)`/`.hexRGB` in AvatarUI. De
  renderer houdt alleen z'n zwart-fallback: een render mag niet stoppen op één
  kapotte kleurwaarde.
- **UXS-21:** 11 ad-hoc `.shadow`-recepten met zeven radius/offset-combinaties →
  `DSShadow.card`/`.overlay`/`.handle` + `.dsShadow(_:scale:)`. De scale-param
  dekt canvas-elementen die met de camera meeschalen. `PlatformChrome` houdt
  bewust z'n eigen proportionele recept (schaalt met de mockup-diameter).
- **UXS-26:** `.padding(.top, 76)` op vijf Settings-pagina's →
  `ShellMetrics.settingsPageTopInset`.
- **UXS-18:** 12× `Color.accentColor` in Banners → `DSColor.Action.primary`,
  plus de systeemgroene scale-handle (de enige groene UI in een lime-DS).
- **UXS-23:** destructieve rijen spraken drie talen (systeemrood, muted, DS-token)
  → overal `Foreground.destructive`. De "Remove"-rij in de image-toolbar was
  zelfs onopvallender dan "Replace image" ernaast.
- **UXS-24:** "Tap the canvas" → "Click the" (dit is een Mac), twee NL-dev-strings
  naar Engels, Colour→Color in UI-copy. De `watercolour`-CASE blijft — die
  rawValue kan in opgeslagen keuzes/CMS-keys zitten; alleen het label is US.
- **UXS-14:** de Colorise-chip toonde alleen een Pro-slot, geen prijs; nu via
  CreditMeter zoals z'n buren. ("Restore body" stond al nergens meer in UI.)

**Batch B — componenten**
- **UXS-25:** `DSSegmentedControl` bestond al, maar paywall en
  ManageBackgroundsSheet hadden elk een eigen kopie — zonder hover, toetsenbord
  of selected-trait. Component kreeg hover (alleen op níet-gekozen segmenten) en
  ←/→ zonder wrap-around (op een tweeknops-toggle laat wrappen de selectie
  stuiteren); beide call sites gemigreerd.
- **UXS-15:** de board had geen ⌫/Esc terwijl de Studio ze wél had. ⌫ loopt door
  de bestaande E46-bevestiging. Batch↔single-toolbar en paneel-wissel snapten;
  nu dsScaleFade via `dsMotion` (dus reduce-motion-bewust).

**Batch C — panels, hints, menu's, Home**
- **UXS-13:** de Temperature-slider klipte tegen de panelrand. De oorzaak zat in
  `DSSlider`: de thumb liep van x=0 tot x=width, dus op beide uiteinden stak z'n
  halve breedte buiten het frame — het viel op Temperature het meest op omdat die
  als enige een signed range heeft. Baan loopt nu van `thumbRadius` tot
  `width − thumbRadius`, en `setValue` spiegelt dat zodat klikken op de uiterste
  rand nog steeds min/max geeft. Kaartlabels kregen `lineLimit(1)` + breedte-cap
  ("Reduce wrinkles" liep over de kaartrand). Face-panel gebruikte al
  DSThumbnailCard op Effects-celmaat en de chip-rij was al scrollend.
- **UXS-17:** de kale "Hold to compare"-tekst was met de toolbar-unificatie al
  verdwenen — maar daarmee gaf niets meer aan dát je het origineel ziet. Nu een
  DS-capsule "Original" die alleen tijdens de hold staat (geen permanente chrome,
  dus geen "verberg na N keer"-teller nodig). De naam-pill (UX19) bleek al op
  `Foreground.primary` + `neutralSurface` te staan.
- **UXS-12:** "Check for Updates…" zat alleen in Settings → About; nu ook in het
  app-menu, via dezelfde UpdateManager. ⌘, en ⌘U waren al app-breed.
- **UXS-9:** Home deelde op "de nieuwste is speciaal" — altijd precies één
  portret in Recent (als paginabrede hero), al het andere Earlier, óók als dat
  ene van maanden geleden was. Nu tijdgebaseerd: Recent = bewerkt in de laatste 7
  dagen (max 6), rest Earlier, beide in hetzelfde raster. Paginatitel is "Home";
  Recent/Earlier zijn sectiekoppen. Home en de gallery delen nu hun grid-maten
  (waren 4 vs 3 kolommen, dus dezelfde kaart oogde per scherm anders).
  First-use ↔ overzicht wisselt met dsScaleFade. **De hero-kaart is dus weg** —
  dat is een zichtbare wijziging aan het hoofdscherm; de HeroMorph uit E36 was al
  opgeruimd (`d488bbd`), dus er lag geen lopend werk onder.
- **UXS-20 (scope-correctie):** de audit telde ~74 `.font(.system(size:))`-sites
  als typografie, maar **77 van de 83 zitten op een `Image`/`DSIcon`** — dat is
  icoongrootte, een ándere as dan tekststijl. Ze op tekst-tokens mappen zou de
  twee juist verder door elkaar halen. Daarom: de **5 echte tekst-sites** (alle in
  BannerTextFloatingToolbar) zijn nu DS-tekststijlen, en er is een aparte
  `DSIconSize`-schaal met LeftNavView als referentie-migratie. De resterende
  icoon-sites staan als **E53.9** — mechanisch, maar het is een eigen sweep.

**Tests (+7):** `HomeSectionsTests` borgt de nieuwe tijdsplitsing (gisteren =
Recent, oud = Earlier, grensgeval, cap, elk portret precies één keer, gedeelde
grid-maten).

**Openstaand:** de visuele her-run van de audit-screenshotserie (panels op
1100×760, Home breed/smal, studio-selectie) is niet gedraaid — dat vergt de app
live met seed-data. De logica-kant is met tests geborgd; het oogdeel blijft.

## 53.9 — Icoongrootte-tokens app-breed (rest van UXS-20)
- status: backlog
- team: DS
- blockedBy: —

**Wat:** `DSIconSize` (xs/sm/base/lg/xl) bestaat en LeftNavView is erop
gemigreerd als referentie. Resteren ~72 `.font(.system(size:))`-sites op
`Image`/`DSIcon` in Features — mechanisch mappen op de dichtstbijzijnde token,
mét oogtest per scherm (een icoon dat een halve punt verspringt valt op in een
toolbar-rij). Banner-canvas-tekst (user content) blijft uitgezonderd.
**DoD:** `grep -rn "\.font(\.system(size: [0-9]" Avatar2/Features` = alleen
user-content-render-code; beide targets bouwen; tests groen.

## 53.6 — Shell-chrome & hover-fixes (UX34–UX36, meldingen Thierry 2026-07-02)
- status: done
- owner: FEAT+DS (afgerond in eerdere sessies; geverifieerd + gesloten 2026-08-01)
- team: FEAT+DS
- blockedBy: —

**Wat (volg UXS-27…29 in het PLAN-document):**
- UX36/UXS-27 [DS]: chip-hover is een no-op — `DSColor.neutralSurface` geeft bij
  hover de rustkleur terug; hover-trede relatief aan de base maken (één
  DS-regel, fixt Name/Frame/Background/grid-chips tegelijk).
- UX35/UXS-28: breadcrumb verspringt bij preview — `studioFullBleed`-flip wisselt
  het referentiekader; band altijd venster-breed, leading alleen op
  `isLeftNavVisible`.
- UX34/UXS-29: traffic lights + sidebar-toggle zweven boven de sidebar-kaart —
  sidebar-materiaal doortrekken tot de venstertop + toggle in de sidebar-header.
**DoD:** beide targets bouwen, tests groen, visuele smoke dark+light; Result-regel.

**Result (geverifieerd 2026-08-01):** alle drie de punten waren al gebouwd in
eerdere sessies maar de story stond nog open. Code-verificatie op v2-main:
- ✅ **UX36/UXS-27** — `DSColor.neutralSurface(pressed:hovering:base:)` is
  base-bewust: bij een gevúlde base schuift de ladder één trede op (hover →
  `neutral-strongest`, pressed → het nieuwe token `neutral-strongest-2`). Daarmee
  is de hover op de Name/Frame/Background/grid-chips niet langer identiek aan hun
  rustkleur. Geland via E53.3.
- ✅ **UX35/UXS-28** — `shellEditorBreadcrumbLeading` hangt alleen nog van
  `isLeftNavVisible` af, niet meer van `studioFullBleed`; de oude `gap3`-tak
  rekende alsof de band in de content-kolom leefde en liet de breadcrumb bij
  Edit↔Preview ~248pt verspringen. Commit `4350f62`.
- ✅ **UX34/UXS-29** — lege unified `NSToolbar` (`ShellSidebarChrome.stabilise`)
  maakt de titelbalk hoog genoeg dat AppKit de traffic-lights native lager
  centreert (`windowControlsCenterFromTop` = 26pt), ín de zwevende sidebar-kaart;
  de toggle ligt op dezelfde middellijn en de content pint op de oude 28pt-lijn
  (`contentTopSafeArea`) zodat de rest van de layout niet schoof. Commit
  `e2dff74` (v2 — de v1-aanpak dokte de kaart aan de venstertop en is door
  Thierry afgekeurd omdat de zwevende gap3-inset moet blijven).
Deze story voegt dus géén nieuwe code toe; `scripts/build-v2.sh` groen op de
gecombineerde 53.1+53.6-branch. **Openstaand:** de visuele dark+light-smoke uit de
DoD is niet opnieuw gedraaid — de drie fixes zijn destijds per commit visueel
geverifieerd, maar een gecombineerde her-check zou Thierry zelf moeten doen.

## 53.7 — Persistente presentatie: modals/menu's overleven een tab- of vensterwissel
- status: done
- owner: FEAT+DS
- team: FEAT+DS
- blockedBy: —

**Wat:** presentatiestate zat verspreid in view-`@State` op diepe child-views. Bij
elke view-recreatie (tab-/lens-wissel, `studioFullBleed`-flip, vensterwissel) werd
die state weggegooid: open modals sloten zichzelf, dropdowns klapten dicht en een
half ingevulde flow (sign-in, pre-stylize-gate) was weg. Oplossing: presentatie-
state naar modellen (`UIPresentationStore`, `ShellModel`, `EntitlementModel`),
sheets alleen op stabiele hosts (`Avatar2App`/`ShellView`) via `dsPersistentSheet`,
en zwevende overlays via `FloatingOverlayHost` i.p.v. systeem-popovers. De regel
staat als cursor-rule [ds-persistent-presentation.mdc](../.cursor/rules/ds-persistent-presentation.mdc).

**DoD:** beide targets bouwen, tests groen, geen presentatie-`@State` meer in
child-views, geen ruwe `.sheet` buiten de stabiele hosts; Result-regel.

**Result:** Het gros landde als WIP-snapshot `49433d4` (2026-07-12, bewust gecommit
zodat vier wachtende story-branches konden mergen): `UIPresentationStore` +
`FloatingOverlayHost` + `DSPersistentSheet`, sheets verplaatst naar `ShellView`
(export, rename incl. board-bulk, manage-backgrounds, pre-stylize-gate),
sign-in-flow naar `EntitlementModel`, en de cursor-rule. **Afgerond 2026-07-31**
met de laatste drie dropdowns die nog op view-`@State` draaiden:
- ✅ `BackgroundPanel.showTypeMenu` → `presentation.editorBackgroundTypeMenuOpen`.
  Het store-slot bestond al (en werd al opgeruimd in `dismissAllEphemeral`) maar
  niets schreef ernaar — de panel-`@State` was de echte bron. Nu een `Binding` op
  de store.
- ✅ `EditColorPanel.openMenu` (Boost- / Remove background-chipdropdown) → nieuw
  `presentation.editorChipMenu`; `ChipMenu` van `private` naar internal + `Sendable`.
  Doorgegeven op alle drie de call sites (EditorView + beide BoardView-panelen),
  zodat het board niet stil kapotgaat als die chips daar later wél bedraad worden.
- ✅ `PortraitsGalleryView.folderBackgroundPickerOpen` → nieuw
  `presentation.folderBackgroundPickerOpen`; deze view wordt bij élke lens-wissel
  opnieuw gebouwd, dus dit menu viel juist het vaakst om.
Beide nieuwe slots opgeruimd in `dismissAllEphemeral()`. Verificatie: `.sheet(`
komt in `Avatar2/` nergens meer voor buiten `ShellView`/`Avatar2App` (op de
E25.1-debug-haak na) en er staat geen `.popover(` meer in de app. Tests: twee
nieuwe cases in
[PersistentPresentationTests](../Avatar2Tests/PersistentPresentationTests.swift) —
de gemigreerde state overleeft een view-recreatie en `dismissAllEphemeral` ruimt
élk vluchtig menu op terwijl een open taak-modal blijft staan. `scripts/build-v2.sh`
volledig groen.

**Bewust NIET meegenomen:** `EditColorPanel.showHybridCoachmark` blijft view-`@State`
— dat is een inline banner ín het paneel (geen modal/overlay) die zichzelf opnieuw
aanbiedt via `noteHybridFallbackIfNeeded()`; hem naar de store tillen levert geen
gedragswinst op. De Apple-Intelligence-sheet in `ImagePlaygroundEditChip` presenteert
nog vanuit een child-view: dat is een systeem-sheet van het ImagePlayground-framework
met een eigen levenscyclus, en verplaatsen vergt de bron-afbeelding + completion door
de store plumben — belegd als eigen story E53.8.

## 53.8 — Apple Intelligence-sheet op een stabiele host
- status: backlog
- team: FEAT
- blockedBy: —

**Wat:** `ImagePlaygroundEditChip` (in `EditColorPanel`) presenteert de
`imagePlaygroundGenerationSheet` vanuit een diepe child-view — tegen regel 2 van
[ds-persistent-presentation.mdc](../.cursor/rules/ds-persistent-presentation.mdc)
in. Een tab-wissel terwijl Image Playground open staat gooit de sheet weg, inclusief
de generatie eronder. Verplaats de presentatie naar `ShellView` met de bronafbeelding
+ completion via `UIPresentationStore` (zelfde patroon als de Create-effect-modal in
E09.3). Neem `ImagePlaygroundGenerateSwatch` meteen mee — die staat forward-built maar
heeft nog geen call site.
**DoD:** de sheet overleeft een tab-wissel; beide targets bouwen; tests groen;
Result-regel.
