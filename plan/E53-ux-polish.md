# E53 — UX-polish n.a.v. UX-audit 2026-07-02

Team: **FEAT + DS**

Bron: `plan/AUDIT-UX-2026-07-02.md` (33 bevindingen: 8×P0, 15×P1, 10×P2) +
`plan/PLAN-UX-POLISH-2026-07-02.md` (story-ready uitwerking: UXS-1…UXS-26 met
exacte bestanden/regels, code-aanpak en acceptatiecriteria — gebruik dát als
implementatiebron). Dit epic mapt sprint 1 (P0) op 53.1–53.4; sprint 2/3 = 53.5.

---

## 53.1 — Polish-sprint S-items (top-10 #1–#7)
- status: in_progress
- owner: FEAT (2026-07-31, branch v2/e53-1-polish)
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

## 53.2 — Banner Studio bruikbaarheid (UX1 + UX2, P0)
- status: in_progress
- owner: FEAT (2026-07-12, checkpoint op branch v2/e53-2-banner-studio)
- team: FEAT
- blockedBy: — (E53.7 is af; UX2 kan gebouwd worden)

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
- status: ready
- team: DS
- blockedBy: —

**Wat:** respecteer "Reduce motion" overal (raakt ook UX16/UX33); centraliseer in
een DSMotion-helper i.p.v. per-view checks.
**DoD:** met reduce-motion aan zijn alle transities cross-fade/instant; tests
groen; Result-regel.

## 53.5 — P1/P2-restlijst (backlog)
- status: backlog
- team: FEAT+DS
- blockedBy: 53.1

De overige P1/P2-bevindingen uit `AUDIT-UX-2026-07-02.md` (UX8, UX12–UX27,
UX31–UX33) — oppakken in een volgende polish-ronde; UX6 (update-flow
relaunchAndInstall zonder call sites) hoort bij E13-releasewerk.

## 53.6 — Shell-chrome & hover-fixes (UX34–UX36, meldingen Thierry 2026-07-02)
- status: in_progress
- owner: FEAT+DS (2026-07-31, branch v2/e53-1-polish)
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
