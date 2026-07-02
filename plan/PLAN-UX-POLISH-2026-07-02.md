# PLAN-UX-POLISH — story-ready uitwerking van AUDIT-UX-2026-07-02

**Bron:** `plan/AUDIT-UX-2026-07-02.md` (36 bevindingen: 8×P0, 18×P1, 10×P2 —
UX34–UX36 nagemeld door Thierry tijdens live review, cluster E → stories UXS-27…29).
Elke story hieronder is zelfstandig implementeerbaar: bevinding(en), waarom, bestanden,
concrete aanpak, acceptatiecriteria (AC) en verificatie. Regelverwijzingen zijn
geverifieerd op de werkboom van 2026-07-02. Afhankelijkheden op de CTO-audit
(`AUDIT-CTO-2026-07-01.md`) staan expliciet vermeld — dubbel werk vermijden.

**Volgorde:** Sprint 1 = alle P0's (≈2–3 dagen). Sprint 2 = P1-flows. Sprint 3 =
P2-hygiëne (sweeps, mag opportunistisch mee met ander werk in dezelfde files).

**Correctie t.o.v. de audit (bij implementatie ontdekt):** `DSThumbnailCard`
(AvatarUI, panel-tiles) heeft wél een donkere label-scrim én `dsHoverScale()` —
het light-mode-contrastprobleem (UX5) zit in de *gallery*-kaart
(`PortraitsGalleryView.swift:244-253`), niet in de DS-component. UXS-3 en UXS-7
richten zich daarom op de gallery-kaart; de hover-claim uit UX26 is voor
DSThumbnailCard vervallen.

---

## Sprint 1 — P0-defecten

### UXS-1 · Escape annuleert tekst-edit (UX3) — S
**Waarom:** macOS-conventie: Esc = cancel. Nu committen Esc en Enter identiek.
**Bestanden:** `Avatar2/Features/Banners/BannerInlineTextField.swift:108-115` (+ de
call site die `onSubmit` levert, vermoedelijk `BannerCanvasTextChrome.swift`).
**Aanpak:**
1. Bij edit-start de originele tekst vastleggen (property op de editing-state of
   meegeven aan de field: `originalText`).
2. In `doCommandBy`: de gecombineerde branch splitsen —
   `insertNewline` → `onSubmit()`; `cancelOperation` → nieuw callback
   `onCancel()` dat `text = originalText` zet en dáárna dezelfde
   end-editing-route volgt als submit (first responder loslaten, chrome sluiten).
3. Edge case: was de laag nieuw (placeholder, nog niets getypt) → `onCancel` gedraagt
   zich als `onDeleteWhenEmpty()` zodat er geen lege laag achterblijft.
**AC:** Esc tijdens edit herstelt exact de tekst van vóór de edit; Esc op een verse
laag verwijdert die laag; Enter en click-away committen zoals nu; undo-stack krijgt
géén entry van een geannuleerde edit.
**Verificatie:** live in de studio (`--enable-banners`): typ → Esc → origineel terug;
nieuw tekstblok → Esc → laag weg; unit-test op de coordinator als die testbaar is.

### UXS-2 · Toast-betrouwbaarheid (UX4 + UX31) — S/M
**Waarom:** fouten verdwijnen te vroeg, worden ingeslikt, of de close-knop doet niets.
**Bestanden:** `Avatar2/Avatar2App.swift:153-179`, `Avatar2/Features/Shell/ShellView.swift:117-…`
(busy-toast met lege closure), `Avatar2/Features/Paywall/SignInSheet.swift:57`,
`EntitlementModel.swift:258-264`, `AvatarUI/Sources/AvatarUI/Components/DSToast.swift`.
**Aanpak:**
1. **Timer-reset:** `.task { … }` op de error-toast (Avatar2App.swift:168) →
   `.task(id: message) { … }` zodat een vervangende melding de volle duur krijgt.
2. **Prioriteit i.p.v. slot-volgorde:** de `if/else`-keten (:154-172) toont nu
   OutOfCredits > Working > Error. Minimaal: error vóór working plaatsen (een fout
   mag een spinner verdringen — de operatie ís gefaald). Netter: klein
   `ToastQueue`-reducer-object in EntitlementModel dat één actieve toast kiest op
   prioriteit error > outOfCredits > working.
3. **Dode close-knop:** ShellView.swift:119 `DSToast(title:){}` — closure wiren aan
   het echte dismiss-pad van die busy-state, óf DSToast een init zonder close-actie
   geven die de knop niet rendert (knop-die-niks-doet mag niet bestaan).
4. **Duurbeleid (UX31):** constanten centraliseren op EntitlementModel:
   `errorToastDuration` (8s, bestaat), `infoToastDuration` (5s) — SignInSheet en
   OutOfCredits daarop aansluiten i.p.v. eigen literals.
5. **Hover-pauze:** in DSToast een `onHover` die een `isPaused`-binding zet; de
   `.task`-loop slaapt in stapjes (bv. 0.25s) en telt alleen af als niet gehoverd.
**AC:** twee fouten kort na elkaar → tweede is volle 8s zichtbaar; fout tijdens
busy-toast is zichtbaar (busy verdrongen of gequeued); elke gerenderde close-knop
dismisst; hover bevriest de timer; geen literal-durations meer buiten het model.
**Verificatie:** unit-tests op de queue-reducer (prioriteit + duur); live: forceer
fout tijdens working-state (bv. netwerk uit + cloud-actie).

### UXS-3 · Gallery-kaartlabels altijd leesbaar (UX5) — S
**Waarom:** in light mode is wit-op-lichtgrijs onder de 4.5:1 (screenshots
`31-light-home.png`, `32-light-portraits.png`).
**Bestanden:** `Avatar2/Features/Shell/PortraitsGalleryView.swift:244-253` (scrim +
label), zelfde patroon checken in `HomeView.swift` (hero + Earlier-kaarten) en
`Avatar2/Features/Banners/…GalleryView` (banner-kaarttitels staan al ónder de kaart —
alleen de Home-bannersectie checken).
**Aanpak:** de scrim foto-onafhankelijk maken: gradient `.clear → .black.opacity(0.55)`
verhogen naar ≥0.75 eindopacity en de gradient-hoogte iets vergroten, óf (netter, één
plek) een klein `DSCardLabelScrim`-component in AvatarUI dat gradient+labelstijl
bundelt en in beide galleries + Home gebruikt wordt. Witte labeltekst blijft dan
correct in beide themes omdat de ondergrond gegarandeerd donker is.
**AC:** contrast label↔scrim ≥ 4.5:1 gemeten op de lichtste kaart (cutout op
`Background.neutral` in light mode); dark mode visueel onveranderd.
**Verificatie:** screenshots light/dark vóór/na; pixel-sample van de scrim onder het
label.

### UXS-4 · "Restore to original" in DS-stijl + juiste laag (UX7) — S
**Waarom:** enige system-blauwe knop in de editor, overlapt bovendien de toolbar
(`12-overflow.png`).
**Bestanden:** editor-overflowmenu — `Avatar2/Features/Editor/EditorView.swift`
(overflow/⋯-menu rond :500, zie ook CTO-C4 over de undo-naam).
**Aanpak:** de losse `Button` met default `.buttonStyle` vervangen door dezelfde
DS-menu-rij als de overige overflow-items (destructive-variant — zie UXS-23; tot die
er is: `DSColor.Signal.error` als tint). Z-order/plaatsing binnen het menu-popover
fixen zodat 'ie niet over de toolbar rendert maar ín het menu leeft.
**AC:** geen `.borderedProminent`/accent-blauw meer in het editor-overflowmenu; item
rendert binnen het menu; werking (restore + confirm) ongewijzigd.
**Verificatie:** screenshot overflow-menu; grep op `buttonStyle(.bordered` in
Features/Editor.

### UXS-5 · Banner-thumbnails zonder placeholder-soep (UX1) — M
**Waarom:** thumbnails tonen 9× "Type to enter text" (`18c-banners-gallery.png`);
zichtbaarste defect zodra de banners-flag aan gaat.
**Bestanden:** `Avatar2/Features/Banners/BannerDocRenderer.swift` (render-pass),
`BannerTextPresets.isEmptyOrPlaceholder` (bestaat al —
`BannerInlineTextField.swift:119` gebruikt 'm), `BannerPlaceholderMigration.swift`
(bestaat al: doc-brede sweep — aanhaken, niet dupliceren), thumbnail-cache/herbake in
`BannerPreviewView.swift` of het gallery-model.
**Aanpak:**
1. **Render-guard (het vangnet):** in de tekstlaag-loop van BannerDocRenderer lagen
   overslaan waar `BannerTextPresets.isEmptyOrPlaceholder(layer.text)` — zowel in de
   thumbnail- als de export-pass (een export met placeholder-tekst is hetzelfde
   defect in het kwadraat).
2. **Data-opruiming:** `BannerPlaceholderMigration` doc-breed draaien (niet
   selectie-gescoped — CTO-B6) bij openen van een banner én eenmalig over bestaande
   docs; daarna previews herbaken zodat de gallery direct schoon is.
3. **Canvas:** placeholder-lagen blijven op het canvas wél zichtbaar (daar zijn ze
   affordance), alleen renders/thumbnails slaan ze over.
**AC:** gallery + Home-bannersectie tonen geen placeholder-tekst meer voor banner
"One" (bestaand testdoc); export van een doc met resterende placeholder-laag bevat
die laag niet; canvas-gedrag ongewijzigd.
**Verificatie:** unit-test op de renderer (doc met 1 echte + 2 placeholder-lagen →
alleen echte in output, bv. via pixel/attributed-inspectie); live screenshots.

### UXS-6 · Banner Studio: fit-to-window + zoom (UX2) — M
**Waarom:** canvas (1500×500) valt buiten een 1100×760-venster; geen enkele zoom-UI
(`19-banner-studio.png`).
**Bestanden:** `Avatar2/Features/Banners/BannerStudioView.swift` (canvas-container,
raw zooms op :119-125), gedeelde chip uit UXS-16.
**Aanpak:**
1. Canvas in een schaal-container: `scale = min(1, (viewW - inset) / docW,
   (viewH - chromeH) / docH)`, toegepast bij openen en bij venster-resize
   (GeometryReader), tenzij de gebruiker handmatig gezoomd heeft (flag reset bij
   "Fit").
2. Zoom-chip (uit UXS-16) rechtsonder: toont %, klik = fit, ⌘+/⌘-/⌘0 binden zoals de
   editor.
3. Bestaande zoom-animaties door `DSMotion.animate` (valt samen met UXS-19).
**AC:** studio openen op 1100×760 → hele canvas zichtbaar incl. selectie-handles;
resize venster → canvas blijft passen (tot de gebruiker zelf zoomt); zoom-chip toont
live %.
**Verificatie:** live op 1100×760 én 820×620; screenshot vóór/na.

### UXS-7 · Kaarten toegankelijk maken (UX28 + UX29) — M
**Waarom:** portret-/bannerkaarten exposen géén AX-elementen; VoiceOver kan de kern
van de app niet bedienen (live geverifieerd). Plus lege labels op icon-knoppen
app-breed.
**Bestanden:** `Avatar2/Features/Shell/PortraitsGalleryView.swift` (kaart-view),
`HomeView.swift` (hero + secties), banners-gallery-kaart,
`Avatar2/Features/Portraits/LibraryViewSwitcher.swift` (lege labels),
`AvatarUI/Sources/AvatarUI/Components/DSIconButton.swift` + call sites
(`PaywallSheet.swift:70,105,134`, `PrivacyElevationSheet.swift:25`,
`WorkingToastView.swift:45`, `FirstUseEmptyState.swift:90`),
`BoardView.swift:898,924-927` (6 align-knoppen), `BannerTextFloatingToolbar.swift`,
`ManageBackgroundsSheet.swift:53,199`, `HairPanel.swift:168`,
`ClothesPanel.swift:167`, `GalleryLens.swift:86-97`.
**Aanpak:**
1. **Kaarten:** op de kaart-root `.accessibilityElement(children: .ignore)`,
   `.accessibilityLabel(portrait.name.isEmpty ? "Untitled portrait" : portrait.name)`,
   `.accessibilityAddTraits(.isButton)` (+ `.isSelected` bij selectie) en een
   `.accessibilityAction { open(portrait) }`. De kaart-tap zit nu vermoedelijk in een
   `onTapGesture` — die blijft; de AX-action roept dezelfde closure aan.
2. **DSIconButton:** `label`-parameter zonder default maken (compilerfout dwingt alle
   call sites) en intern `.accessibilityLabel(label)` + `.help(label)` zetten.
3. **Sweep:** resterende lege-label-knoppen uit de lijst hierboven voorzien van
   labels ("Align left", "Grid view", …).
**AC:** `axdump` (scratchpad-tool) toont voor elke kaart een AXButton met naam; alle
knoppen in de genoemde files hebben een niet-lege AX-label; VoiceOver-cursortest op
Home kan een portret openen.
**Verificatie:** her-run van de audit-AX-dump; VoiceOver-smoke (⌘F5) op Home,
gallery, paywall.

### UXS-8 · Update-flow afmaken (UX6 — samen met CTO-C1) — M
**Waarom:** "Check now" geeft geen uitkomst-feedback, "relaunch to install" is nergens
gewired, progress wordt nooit gevoed. Dit is release-kritisch voor een DMG-app.
**Bestanden:** `Avatar2/Features/Settings/SettingsAboutPage.swift:19,35`,
`Avatar2/UpdateManager.swift:183-185,228-232,243-245`.
**Aanpak (bovenop CTO-C1's app-brede updater):**
1. `UpdateManager` een expliciete state machine geven:
   `idle / checking / upToDate / downloading(progress) / readyToRelaunch / failed(msg)`
   — de Sparkle-delegate-callbacks (die nu deels leeg zijn, :228-245) mappen op deze
   states.
2. About-UI bindt op die state: "Check now" → spinner in de knop; `upToDate` → korte
   inline bevestiging "You're up to date (1.2.1)" (geen toast nodig, de gebruiker
   kijkt al hier); `downloading` → determinate progress; `readyToRelaunch` → knop
   "Relaunch to install" die éíndelijk `relaunchAndInstall()` aanroept.
3. `failed` → inline `Signal.error`-tekst met retry.
**AC:** elke "Check now" eindigt zichtbaar in upToDate/downloading/failed; de
relaunch-knop bestaat en werkt (Sparkle-testfeed); geen belofte-copy meer zonder
gewirde actie.
**Verificatie:** tegen de appcast-testfeed (zie memory: release-URL/appcast-implicaties
bij de repo-transfer) een lagere lokale versie installeren en de hele flow doorlopen.

---

## Sprint 2 — P1-flows & schermen

### UXS-9 · Home: eerlijke secties, begrensde hero (UX8) — M
**Bestanden:** `Avatar2/Features/Shell/HomeView.swift:40-46,78-87,330+`.
**Aanpak:**
1. Sectie-logica: `Recent` = portretten met `modifiedAt` in de laatste 7 dagen
   (cap op 6), rest = `Earlier`; geen featured-vs-rest meer. Leeg Recent → sectie
   verbergen, gewoon de grid tonen.
2. Hero: geen kaart op paginabreedte; Recent rendert in dezelfde grid-celmaat als
   Earlier (eventueel 1 rij groter, max-hoogte ~320pt).
3. "Recent"/"Earlier" als sectiekop-stijl (`DSTextStyle.h3`-equivalent), niet als
   paginatitel; paginatitel wordt "Home".
4. First-use ↔ overzicht wisselt met `dsScaleFade` (`HomeView.swift:40-46`).
5. Grid gelijktrekken met de gallery (kolommen/gap — één const in ShellMetrics) en
   één hover-behandeling (dsHoverScale) voor alle kaartsoorten.
**AC:** een gisteren bewerkt portret staat in Recent, een oud portret niet; hero
≤320pt hoog; geen snap bij first-use-wissel; Home en gallery delen gridmaten.
**Verificatie:** smoke met SmokeSeed-data (recente + oude items); screenshots
breed/smal.

### UXS-10 · Upload-pill maskeert geen content (UX9) — S
**Bestanden:** `Avatar2/Features/Shell/ShellView.swift:238-247` (bottom-overlays),
`HomeView.swift:330` (pill), `PortraitsGalleryView.swift` (scroll-lenzen).
**Aanpak:** de scroll-lenzen krijgen een bottom `contentMargins`/`safeAreaPadding`
ter hoogte van pill + gap (gemeten hoogte, zelfde patroon als de header-inset die
PortraitsGalleryView al gebruikt — zie de comment op :40-50 waarom safeAreaInset op
de container zelf niet kan met de board-lens; de inset hoort dus per scroll-lens,
niet op de ZStack). Board-lens: pill daar niet tonen of node-layout onder de pill
vrijhouden.
**AC:** laatste kaartrij is volledig boven de pill uit te scrollen in Home én alle
scroll-lenzen; pill blijft op z'n plek.
**Verificatie:** scroll naar de bodem in Home/grid/lijst op 820×620 en 1100×760.

### UXS-11 · Paywall + Account copy-pass (UX10 + UX11) — S
**Bestanden:** `Avatar2/Features/Paywall/PaywallSheet.swift` (kaarten, :163-180
segmented), `Avatar2/Features/Settings/SettingsAccountPage.swift` (credits-copy).
**Aanpak:**
1. Starter-kaart: badge "Current plan" (neutrale stijl) wanneer
   `entitlement.tier == .starter`; Pro-kaart houdt "Upgrade". Op Pro-accounts
   andersom.
2. Fix dubbele ✕: de settings-close (rechtsboven het venster) verbergen zolang een
   sheet gepresenteerd is (of de paywall als echte `.sheet` boven een gedimde
   settings laten — één close-affordance tegelijk).
3. CTA "Upgrade to pro" → "Upgrade to Pro"; features-copy: "No bots" → concrete
   waarde (bv. "Human support"); prijs via `Decimal` + `NumberFormatter` met
   `Locale.current` i.p.v. hardcoded "€49,90"-string.
4. Account: credits-subtekst conditioneel — Starter mét saldo: "Top-up credits — you
   can use these on any plan"; Starter zonder: "Credits come with a Pro plan";
   Pro: refill-datum (mét de verleden-datum-guard uit CTO-B8).
**AC:** Starter-account ziet "Current plan" op Starter; exact één ✕ zichtbaar;
prijsweergave volgt systeemlocale; geen zelf-tegensprekende credits-copy meer.
**Verificatie:** screenshots paywall op Starter- en (test-)Pro-account; locale-switch
en-US vs nl-NL.

### UXS-12 · Platform-menu's wiren (UX12) — M
**Bestanden:** `Avatar2/Avatar2App.swift` (Scene/commands),
`Avatar2/Features/Settings/…` (takeover-presentatie).
**Aanpak:**
1. `⌘,`: een `CommandGroup(replacing: .appSettings)` die de bestaande
   settings-takeover opent (zelfde route als het user-menu-item) — géén aparte
   `Settings`-scene naast de takeover (twee settings-UI's is erger).
2. `CommandGroup(after: .appInfo)`: "Check for Updates…" → UpdateManager (UXS-8).
3. File-menu: "Upload Portrait… ⌘U" als `Command`, enabled zodra de shell actief is
   (nu werkt ⌘U alleen via de pill op een niet-lege Home — CTO-D6).
4. Edit/View-menu's: items die contextueel disabled zijn is prima; items die nóóit
   enabled kunnen worden verwijderen.
**AC:** ⌘, opent Settings vanaf elk scherm; "Check for Updates…" bestaat in het
app-menu; ⌘U werkt op Home én gallery; menu-dump zonder permanent-dode items.
**Verificatie:** `axmenu`-dump vóór/na; shortcuts live testen.

### UXS-13 · Editor-panels: clipping + één card-taal (UX13 + UX14) — M
**Bestanden:** Enhance-panel (Temperature-slider + chip-row), Effects-panel (grid),
`Avatar2/Features/Editor/…Panel.swift`, `AvatarUI …/DSThumbnailCard.swift` (goede
basis — al scrim/hover/badges).
**Aanpak:**
1. Enhance: panel-inhoud in een `ScrollView` met vaste max-hoogte óf panelhoogte op
   content sizen; chip-row horizontaal scrollend i.p.v. truncerend ("Boos…").
2. Effects: grid-kolommen `adaptive(minimum:)` i.p.v. vaste maten zodat de laatste
   kolom niet clipt op panelbreedte.
3. Face-panel migreren naar dezelfde DSThumbnailCard-presentatie als Effects
   (foto-thumbs; de CMS levert per preset al een still — zie E33-presets). Zolang er
   geen still is: icoon gecentreerd op `Background.neutral` (bestaand
   DSThumbnailCard-pad), maar zelfde celmaat als Effects.
4. Copy: "Reduce wrinkles" → "Smooth wrinkles" of celbreedte verruimen; labels op
   1 regel (`lineLimit(1)` + `minimumScaleFactor` niet gebruiken — kies kortere copy).
**AC:** geen geclipte slider/cards op de standaard panelmaat; Effects en Face delen
celmaat + card-stijl; geen truncatie in chip-rows (scrollbaar).
**Verificatie:** screenshots van alle 6 panels op 1100×760 (her-run van de
audit-serie 07–11).

### UXS-14 · Eén naam voor "Fill in body" + credit-chips compleet (UX15) — S
**Bestanden:** `Avatar2/AIFeatureRegistry.swift:22`,
`Avatar2/Features/…/PrivacyElevationSheet.swift:33`, `PrivacyFeatureMatrix.swift:59`,
`Avatar2/Features/Editor/EditColorPanel.swift:53-56,178`.
**Aanpak:** `AIFeature.restoreBody.uiLabel` → "Fill in body" (case-naam mag blijven);
grep op "Restore body" over de hele app (ook undo-naam — CTO-C4 pakt de undo-kant);
Colorise-chip krijgt z'n credit-prijs via `CreditMeter.chipLabel` zoals de buren
(één prijsbron, sluit aan op CTO-C8).
**AC:** de string "Restore body" komt in de UI nergens meer voor; elke betaalde chip
in EditColorPanel toont een prijs uit CreditMeter.
**Verificatie:** `grep -rn "Restore body" Avatar2` = 0 UI-hits; screenshot
privacy-sheet + panel.

### UXS-15 · Board: transities + toetsenbord (UX16) — S
**Bestanden:** `Avatar2/Features/Board/BoardView.swift:184-209` (toolbar-wissel),
`:1218-1258` (panel-wissel), `:783-788` (key-handling),
referentie `BannerStudioView.swift:164-176`.
**Aanpak:** toolbar- en panel-wissels wrappen in `DSMotion.animate(.fast)` met
`dsSlide`/`dsScaleFade`-transitions (zelfde recept als de editor-panels);
`.onDeleteCommand { deleteSelection() }` + Esc (`onExitCommand`) = selectie leeg —
gedrag 1:1 overnemen van BannerStudio zodat beide canvassen gelijk reageren.
**AC:** batch↔single toolbar en panel-wissel animeren (≤200ms, ease-out, respecteert
reduce-motion); ⌫ verwijdert selectie (met bestaande confirm), Esc deselecteert.
**Verificatie:** live board-smoke; reduce-motion aan → wissels zonder beweging.

### UXS-16 · Eén zoom-chip voor drie canvassen (UX17) — M
**Bestanden:** nieuw `AvatarUI …/DSZoomChip.swift`;
`EditorView.swift:680-696` (huidige reset-chip), `BoardView.swift:1367-1378`
("Fit"-chip), `BannerStudioView.swift` (via UXS-6).
**Aanpak:** klein DS-component: toont afgerond percentage, klik = fit-to-window,
menu (long-press/klik-pijltje) met 50/100/200%/Fit; bindt op een
`ZoomState`-protocolletje (get/set scale, fitScale) dat elk canvas al bijna heeft.
Shortcuts consistent: ⌘+/⌘-/⌘0 overal (de `⌘=`-variant komt uit CTO-C2).
**AC:** alle drie de canvassen tonen dezelfde chip op dezelfde plek (rechtsonder);
% klopt live; klik = fit op alle drie.
**Verificatie:** editor, board, studio na elkaar; AX-label "Zoom level, 100%".

### UXS-17 · Canvas-hints & naam-pill (UX18 + UX19) — S
**Bestanden:** compare-hint (EditorView, zoekterm "Hold to compare"), naam-pill op de
editor-canvas.
**Aanpak:** compare-hint in een DS-capsule (neutralSurface-achtergrond, labelSmall,
zelfde stijl als de zoom-chip) en na 2× gebruik van compare permanent verbergen
(`@AppStorage`-teller); naam-pill: tekst naar `DSColor.Foreground.primary` op
`neutralSurface(pressed:hovering:)`-achtergrond zodat 'ie in beide themes haalt.
**AC:** hint leest als UI-element (capsule) en verdwijnt na gebruik; naam-pill
≥4.5:1 in dark én light.
**Verificatie:** screenshots; contrast-sample.

### UXS-18 · Banners-selectie in DS-kleuren (UX20) — S
**Bestanden:** Banners-suite, 12× `Color.accentColor` + groene resize-handles
(o.a. `BannerCanvasSelection.swift`, `BannerCanvasTextChrome.swift`,
`BannerCanvasImageChrome.swift`, `BannerCanvasMultiSelectChrome.swift`).
**Aanpak:** sweep `Color.accentColor` → `DSColor.Action.primary` (selectieranden,
marquee, handles); handle-vulling wit met Action-rand zoals de editor-handles zodat
beide canvassen dezelfde selectie-taal spreken.
**AC:** `grep -rn "accentColor" Avatar2/Features/Banners` = 0; selectie-chrome
visueel identiek aan de editor.
**Verificatie:** studio-screenshot met tekst- én imageselectie.

### UXS-19 · Reduce-motion-sweep (UX30 + UX33) — M
**Bestanden:** ~20 sites: `EditorView.swift:651,682`,
`BoardView.swift:796,800,1038,1065,1081`, `BannerStudioView.swift:119-125`,
`Avatar2App.swift:140,175-179,196`, rest via grep
`withAnimation\(|\.animation\(\.(spring|easeOut|easeInOut)`.
**Aanpak:** alle raw `withAnimation`/`.animation` in app-code vervangen door
`DSMotion.animate`/DSMotion-tokens (de API bestaat en is reduce-motion-aware; de raw
springs bounce 0.08–0.1 in BoardView mappen op `springSmall`/`springTransform`; de
ad-hoc 0.18s easeOut op `fast`). Daarna een guard in CI/pre-commit:
`grep -rn "withAnimation(\.\|animation(\.ease\|animation(\.spring" Avatar2 | grep -v DSMotion`
moet leeg zijn (of een SwiftLint custom rule).
**AC:** met "Reduce motion" aan beweegt er niets meer op zoom/pan/toast/panel-wissel
(cross-fades toegestaan); grep-guard actief.
**Verificatie:** System Settings → Accessibility → Reduce motion aan, smoke door
editor/board/studio; grep-check.

### UXS-27 · Hover-trede relatief aan base — dode hovers op topchips (UX36) — S
**Waarom:** de Name/Frame/Background/grid-chips boven de canvas hebben een hover die
in code bestaat maar niets doet: `neutralSurface` geeft bij hover
`Background.neutralStronger` terug en dat ís al de rustkleur van deze chips.
**Bestanden:** `AvatarUI/Sources/AvatarUI/Tokens/DSSurfaceColor.swift:8-12` (de fix),
consumenten ter controle: `DSBottomToolbar.swift:332-338` (CapsuleSurface,
surface `.secondary` → base `neutralStronger`), `CanvasActionToolbar.swift:73`
(headerRow = `.secondary`), `CanvasFrameChip.swift:30` (zelfde base).
**Aanpak:** de ladder in `neutralSurface` base-bewust maken: bij `base == .clear`
blijft het huidige gedrag (hover → neutralStronger, pressed → neutralStrongest); bij
een gevulde base schuift alles één trede op (hover → neutralStrongest, pressed/active
→ neutralStrongest + bestaande active-ring, of een nieuwe `neutralStrongest2`-token
als de stap te klein blijkt). Oogtest in dark én light. Geen per-chip-fixes — dit is
bewust één DS-regel zodat álle secondary-surface knoppen tegelijk genezen.
**AC:** muis over Name-, Frame-, Background- en grid-chip geeft een zichtbaar
kleurverschil (dark + light); ghost-knoppen (bottom-toolbar) onveranderd; pressed en
active blijven onderscheidbaar van hover.
**Verificatie:** live in de editor; kleursample rust vs hover moet verschillen; grep
dat geen call site zelf ging compenseren.

### UXS-28 · Breadcrumb pixelvast bij Edit ↔ Preview (UX35) — S/M — ✅ DONE `4350f62`
**Waarom:** de breadcrumb verspringt horizontaal bij elke mode-toggle.
**Root cause (geverifieerd):** `studioFullBleed` (`ShellView.swift:29-34`) is false
zodra `isShowingSocialPreview`/`isShowingBannerPreview`; daardoor wisselt
`shellEditorBreadcrumbLeading` (`ShellView.swift:388-396`) van
`LeftNavView.layoutWidth + DSSpacing.gap3` (full-bleed: band spant het hele venster)
naar `gap3` (preview: band leeft in de content-kolom). Twee referentiekaders die net
niet op hetzelfde punt uitkomen → sprong.
**Bestanden:** `Avatar2/Features/Shell/ShellView.swift:341-396`,
`ShellMetrics.swift` (bestaande `editorBreadcrumbLeadingCollapsed`).
**Aanpak:** de topchrome-band áltijd venster-breed leggen (ook in preview) en de
breadcrumb-leading uit één formule laten komen die alleen van `isLeftNavVisible`
afhangt: `leading = isLeftNavVisible ? LeftNavView.layoutWidth + gap3 :
editorBreadcrumbLeadingCollapsed - windowEdgeInset` — onafhankelijk van
`studioFullBleed`. De preview-content zelf blijft in z'n kolom; alleen de band
verhuist naar window-space. Daarna de bestaande `dsMotion(springTransform)` op
`isLeftNavVisible` laten staan (sidebar-toggle mág animeren; mode-toggle niet).
**AC:** Edit↔Preview toggelen verplaatst de breadcrumb met 0px (screenshot-diff);
sidebar in-/uitklappen animeert zoals nu; banner-preview idem.
**Verificatie:** screenshots Edit en Preview over elkaar (pixel-diff op de
breadcrumb-bbox); zelfde test met sidebar dicht.

### UXS-29 · Traffic lights + toggle ín het sidebar-paneel (UX34) — M — ✅ DONE `4350f62`
*(Implementatie: kaart dokt aan de venstertop met vierkante tophoeken/ronde
onderhoeken; chrome-strip vanaf y=0; traffic-lights naar native x=20; toggle bleef op
z'n plek. Bijvangst: DEBUG-smoke-haak `--open-editor` — de kaarten zijn nog niet
AX-bedienbaar (UX28), dus editor-smokes konden de editor anders niet in.)*
**Waarom:** met uitgeklapte sidebar zweven de vensterknoppen en de sidebar-toggle in
een band bóven de afgeronde kaart — oogt als een render-bug (crops
`…/crops/28-settings-about-tl.png`, `31-light-home-tl.png`).
**Bestanden:** `Avatar2/Features/Shell/LeftNavView.swift`,
`ShellSidebarChrome.swift`, `ShellMetrics.swift` (`windowEdgeInset`), venster-setup
in `Avatar2App.swift` (hiddenTitleBar/fullSizeContentView staat al aan).
**Aanpak:**
1. Het sidebar-oppervlak (de kaart) tot `y = 0` van het venster laten lopen wanneer
   de sidebar uitgeklapt is: top-inset van de kaart verwijderen en de bovenste
   hoekradius alleen behouden als de kaart níet tegen de venstertop ligt (of: radius
   behouden maar de titlebar-band meenemen in hetzelfde materiaal, zoals
   Finder/Notes/Arc).
2. De sidebar-toggle-knop verhuist ín de sidebar-header (zelfde rij als de traffic
   lights, rechts uitgelijnd), zodat chrome en paneel één geheel zijn; bij
   íngeklapte sidebar blijft de toggle op z'n huidige vrije plek.
3. Content-padding binnenin compenseren (`ShellMetrics`) zodat "Home" op dezelfde
   y blijft.
**AC:** uitgeklapt: traffic lights + toggle liggen visueel óp het sidebar-materiaal
(dark + light), geen zwarte/witte band erboven; ingeklapt: gedrag als nu; geen
overlap met de eerste sidebar-rij bij smalle vensters.
**Verificatie:** screenshots dark/light uit- én ingeklapt; vergelijk met
Finder-sidebar als referentie.

---

## Sprint 3 — P2 DS-hygiëne (sweeps)

### UXS-20 · Typografie-sweep (UX21) — M
74× `.font(.system(size:))` met schaduwschaal 9/10/11/13/15
(ergst: `BannerTextFloatingToolbar.swift`, `LeftNavView.swift:326,436,477,512`).
**Aanpak:** DSTypography uitbreiden met `xxs (10/11)` en `caption (13)` +
bijpassende DSTextStyles; daarna file-voor-file mappen (9→xxs, 13→caption, 15→sm);
banner-canvas-tekst zelf (user-content) is uitgezonderd. **AC:** grep
`.font(.system(size:` in Features = alleen user-content-render-code.

### UXS-21 · Schaduw-tokens (UX22) — S
7+ ad-hoc recepten (`HomeView.swift:342-343`, `ExportSheet.swift:110`,
`BannerStudioView.swift:359`, …). **Aanpak:** `DSShadow.card` en `DSShadow.overlay`
toevoegen naast `.default`; sites mappen. **AC:** grep `.shadow(color:` buiten
AvatarUI = 0.

### UXS-22 · `Color(hex:)` public (UX23) — S
Parser 3× gedupliceerd (`DSColor.swift:118` internal; kopieën
`BackgroundKit.swift:34-40,188`, `BannerDocRenderer.swift:321-326`).
**Aanpak:** DS-initializer `public` + duplicaten verwijderen; unit-test op 3/6/8-digit
en invalid input (bestaat mogelijk al in AvatarUI-tests — uitbreiden). **AC:** één
implementatie, alle call sites erdoorheen.

### UXS-23 · Destructive-row-token (UX24) — S
Drie stijlen (DSMenuRow-token / raw `Color.red`
`BannerTextFloatingToolbar.swift:234-236` / `Foreground.muted`
`BannerImageFloatingToolbar.swift:94-97`). **Aanpak:** `DSMenuRow.Style.destructive`
(Signal.error-tekst+icoon, error-tint hover-achtergrond); beide banner-toolbars +
UXS-4-rij erop aansluiten. **AC:** alle destructieve rijen visueel identiek; raw
`Color.red` weg uit menu-code.

### UXS-24 · Copy-sweep: NL-strings, spelling, touch-idioom (UX25 + UX32) — S
`SettingsAIModelsPage.swift:210` ("Leeg = productie…" — is een dev-veld: Engels
maken óf achter DEBUG), `OnboardingSplashView.swift:91` ("Asset-placeholder …"),
"Colours"→"Colors" (US-spelling app-breed), "Tap the canvas"→"Click the canvas"
(`BannerStudioView.swift:37-40`, `BannerTextCanvasHint.swift:12`).
**AC:** grep op `[Cc]olour`, "Tap the", en de twee NL-strings = 0 hits in UI-code.

### UXS-25 · DSSegmentedControl (UX26) — M
Hand-gerold in `PaywallSheet.swift:163-180` (Monthly/Yearly) en
`ManageBackgroundsSheet.swift:67-86`. **Aanpak:** DS-component met hover-state
(neutralSurface(hovering:)), keyboard (←/→), AX (`.isSelected`-traits) en de
capsule-stijl van de paywall; beide call sites migreren. **AC:** hover + pijltjes
werken op beide plekken; AX meldt selected-state.

### UXS-26 · Settings-layout zonder magic numbers (UX27) — S
`.padding(.top, 76)` ×5 op de Settings-pagina's. **Aanpak:** één
`SettingsPageContainer` (of const in ShellMetrics) die de top-inset t.o.v. de
takeover-header berekent; pagina's erin wrappen. **AC:** grep `76` in
Features/Settings = 0; visueel identiek.

---

## Volgorde & bundeling (voor de bordindeling)

| Story | Prio | Moeite | Bundel met |
|---|---|---|---|
| UXS-1 Esc-cancel | P0 | S | UXS-5/6 (zelfde suite) |
| UXS-2 Toasts | P0 | S/M | CTO-B3 (fout-UI-contract) |
| UXS-3 Label-contrast | P0 | S | UXS-7 (zelfde kaart-view) |
| UXS-4 Restore-knop | P0 | S | UXS-23 (destructive-token) |
| UXS-5 Thumbnails | P0 | M | CTO-B6 (placeholder-sweep) — voorwaarde banners-flag |
| UXS-6 Studio fit/zoom | P0 | M | UXS-16 (zoom-chip) |
| UXS-7 Kaart-a11y | P0 | M | UXS-3 |
| UXS-8 Update-flow | P0 | M | CTO-C1 (app-brede Sparkle) — release-kritisch |
| UXS-9 Home-secties | P1 | M | — |
| UXS-10 Pill-inset | P1 | S | UXS-9 |
| UXS-11 Paywall/Account copy | P1 | S | CTO-B8 (refill-datum-guard) |
| UXS-12 Menu's | P1 | M | UXS-8 (updates-menu-item) |
| UXS-13 Panel-polish | P1 | M | — |
| UXS-14 Fill-in-body naming | P1 | S | CTO-C4/C8 |
| UXS-15 Board keys/transities | P1 | S | UXS-19 |
| UXS-16 Zoom-unificatie | P1 | M | UXS-6, CTO-C2 |
| UXS-17 Hints & pill | P1 | S | — |
| UXS-18 Banners-DS-kleuren | P1 | S | UXS-1/5/6 |
| UXS-19 Reduce-motion-sweep | P1 | M | UXS-15 |
| UXS-27 Hover-trede (dode hovers) | P1 | S | UXS-25 (zelfde surface-ladder) |
| UXS-28 Breadcrumb pixelvast | P1 | S/M | UXS-29 (zelfde shell-chrome) |
| UXS-29 Traffic lights in sidebar | P1 | M | UXS-28 |
| UXS-20…26 | P2 | S–M | opportunistisch per file |

**Definition of done (alle stories):** build + AvatarKit/AvatarUI `swift test` groen
(package-dir, niet het xcodebuild-scheme); geen nieuwe hardcoded waardes waar een
DS-token bestaat; screenshots vóór/na in de PR; reduce-motion gecheckt bij elke
story die animatie raakt; v2-main-werkafspraak: alleen eigen files stagen (geen
`git add -A`).

*Uitwerking door Claude (senior-PD UX-auditsessie, 2026-07-02) op basis van
AUDIT-UX-2026-07-02; regelnummers geverifieerd op de werkboom van die datum.*
