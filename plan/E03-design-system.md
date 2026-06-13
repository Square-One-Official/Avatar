# E03 — Design system

Team: **DS**

Tokens en componenten 1-op-1 uit Figma (pagina Components). Dark-only.

## 3.1 — Tokens
- status: done
- owner: DS
- blockedBy: E01.3
- DoD: beide targets bouwen, tests groen

Kleuren (lime-accent, dark surfaces), typografie, spacing, radii uit Figma → AvatarUI/Tokens.

**Result:** Dark-mode tokens 1-op-1 uit Figma-variabelen (Stories→Dark-secties) in AvatarUI/Tokens: DSColor (surfaces #000/#1c1917/#292524, lime #d5f466, foregrounds, projects-palet), DSTextStyle/DSTypography (Labels/Body/H1-H6-subset), DSSpacing/DSRadius/DSBorderWidth/DSOpacity/DSShadow; signaalkleuren (error/warning/success/info) komen in geen enkel dark-frame voor en zijn bewust buiten scope; beide targets bouwen groen, testtargets bestaan nog niet (E01.4 open).

## 3.2 — Basiscomponenten
- status: done
- owner: DS
- blockedBy: 3.1
- DoD: beide targets bouwen, tests groen

PrimaryButton (lime pill), Chip, IconButton (circulair), QuotaBadge, Toast.

**Result:** DSPrimaryButton (lime pill, Default/Small), DSIconButton (circulair, fillBrand/ghostNeutral incl. active), DSBadge/DSChip/DSQuotaBadge (Figma "Badge" = chip; alleen fill, outline ongebruikt in dark frames) en DSToast (kaart + timer-track) in AvatarUI/Components; states 1-op-1 via Figma-opacityschaal (hover 75/pressed 50/disabled 25), ghostNeutral via bg-wissel (neutral-stronger dark geïnterpoleerd #ffffff1a, niet opvraagbaar via MCP); beide targets bouwen groen, testtargets nog niet aanwezig (E01.4 open).

## 3.3 — BottomToolbar + EditPanel-container
- status: done
- owner: DS
- blockedBy: 3.2
- DoD: beide targets bouwen, tests groen

6 circulaire tools met lime active-ring. Designbesluit: foto verkleint wanneer paneel actief —
centraal in de container geregeld, consistent voor ALLE panelen.

**Result:** DSBottomToolbar + DSEditPanel(Container) 1-op-1 uit Figma Stories→App/Edit & App/Effects dark (Toolbar 4016:3746, dropdownMenu 4016:13604): toolbar = HStack gap-2/padding gap-2 zonder fill, tools 48×48 cirkel bg neutral met 18pt-medium-icoon, actief = lime ring b-medium + lime icoon, tik op actieve tool deselecteert; paneel = bg Card, r-4xl, kaartpadding gap-2 + sectiepadding gap-5, titel UI/Labels/Base primary, schaduw 0/12/24/-12 zwart 25%. Contract: `DSEditPanelContainer(tools: [DSToolbarItem<ID>], activeTool: Binding<ID?>, photo: () -> Photo, panel: (ID) -> Panel)` stapelt foto (flexibele hoogte) → actief paneel → toolbar met gap-2 en regelt het foto-verkleint-besluit (10 jun) centraal via één spring-animatie — feature-panelen leveren alleen titel+inhoud via `DSEditPanel(title:content:)` en hoeven zelf niets te animeren; undo/redo zijn géén toolbar-items maar losse DSIconButtons (E06); in Figma overlapt het paneel de foto statisch — bewust afgeweken conform bouwplan-designbesluit. Beide targets bouwen groen, AvatarUI-tests groen (3 nieuwe smoke-tests).

## 3.4 — ProChip / credit-gating-component
- status: done
- owner: DS
- blockedBy: 3.2
- DoD: beide targets bouwen, tests groen

Eén gating-patroon voor alle features (les uit v1: niet versnipperen).

**Result:** DSProChip + DSGated in AvatarUI/Components. Figma kent géén los gating-component (review rode draad 3); de chip hergebruikt 1-op-1 de brand-Badge uit 3.2 — de "Upgrade"-taal van topbar en Upgrade Modal (4019:953). Contract: `DSProChip(_ label: String = "Pro")` (lime badge; eigen label voor credit-kosten zoals "2 credits") en `DSGated(isLocked: Bool, chipLabel: String = "Pro", onUpgradeRequested: () -> Void) { content }` — vergrendeld: chip top-trailing (inzet gap-1), eigen interactie van de inhoud uit, élke tik → onUpgradeRequested met de Figma-hover/pressed-opacitystates; ontgrendeld: inhoud onaangeroerd. Credit-tegoed tonen blijft DSQuotaBadge (3.2). Beide targets bouwen groen, AvatarUI-tests groen (2 nieuwe smoke-tests).

## 3.5 — Formulier- en lijstcomponenten
- status: done
- owner: DS
- blockedBy: 3.2
- DoD: beide targets bouwen, tests groen

OTP-veld, tekstveld, panel-headers, sidebar-rij (avatar+naam+rol), add-knop (button-component uit
Figma).

**Result:** Vijf componenten 1-op-1 uit Figma in AvatarUI/Components: DSTextField (Input 59:621 — optioneel muted label, capsuleveld h40 bg neutral, rand b-thin divider→muted bij focus, Body/Small, 20pt leading icon), DSOTPField (OTP 60:798 — 6 cellen px gap-3.5/py gap-5 r-lg met middenstreepje 8×2, placeholdercijfer muted/ingevoerd primary, actieve cel muted rand; invoer via verborgen veld met cijferfilter, `DSOTPField(code: Binding<String>, length: Int = 6)`), DSPanelHeader (Onboarding-Copy-blok — H1 primary + Body/Medium subtle, gap-2, alignment-parameter), DSSidebarRow (Slot 4011:5010 — avatar 48 r-2xl + naam/rol UI/Labels/Base primary/muted, selectie = bg Inset op r-2xl, `DSSidebarRow(name:role:isSelected:action:avatar:)`), DSNeutralButton (Button Fill-Neutral 12:216, zelfde maten als DSPrimaryButton) met DSAddButton (= neutral button + plus-icoon, het sidebar-add-besluit van 10 jun). Beide targets bouwen groen, AvatarUI-tests groen (5 nieuwe smoke-tests).


## 3.6 — Toggle/switch-component
- status: done
- owner: DS
- blockedBy: 3.1
- DoD: beide targets bouwen, tests groen

Online-modellen-toggle uit Figma Onboarding / Permissions (en straks Settings E08.1): AvatarUI
heeft nog geen toggle/switch. Component 1-op-1 uit Figma "Components" (incl. on/off- en
disabled-staten, lime active-state). (Story toegevoegd door FEAT bij E04.3 — AvatarUI is
DS-grens.)

**Result:** DSToggle 1-op-1 uit Figma Toggle (61:944) in AvatarUI/Components: track 48×24 r-full — uit neutral→neutral-stronger (hover)→neutral-strongest (pressed), aan background/action (lime, alle staten); thumb 22 met gap-px-inzet — foreground/default/thumb (uit) resp. on-action (aan), hover schuift thumb 2pt naar binnen, pressed toont thumb alvast aan de doelzijde (zo staan de Figma-pressed-frames erin); Figma kent géén disabled-variant → opacityschaal .25 zoals DSTextField; a11y via accessibilityRepresentation als echte Toggle. Contract: `DSToggle(isOn: Binding<Bool>)`. Beide targets bouwen groen, alle tests groen (2 nieuwe smoke-tests).

## 3.7 — Per-feature-indicatoren: Pro-badge + cloud/AI-glyph
- status: done
- owner: DS
- blockedBy: 3.4
- DoD: beide targets bouwen, tests groen
- Context: DSGated/DSProChip uit 3.4; de requiresCloud-vlag per actie komt uit CreditMeter (E14.3). (Story toegevoegd op besluit Thierry 2026-06-12.)

DSGated/DSProChip uitbreiden met twee subtiele per-feature-indicatoren: (1) Pro-badge op features
die voor free-gebruikers vergrendeld zijn; (2) een cloud/AI-glyph wanneer de feature online vereist
én online uit staat. Tik op een indicator geeft een korte uitleg + route: upgrade (Pro-badge) resp.
Settings > AI & Models (cloud-glyph). Géén modals of blokkades — de indicatoren informeren, het
bestaande DSGated-gedrag blijft het enige gate-mechanisme.

**Result:** DSFeatureIndicator (.pro = brand-chip, .cloudOff = cloud-glyph in neutral cirkel à la Icon-Only Button Small) in AvatarUI/Components: tik → popover (geen modal) met één regel uitleg + route-knop in lime (Upgrade resp. "Open AI & Models settings"). DSGated uitgebreid (source-compatible): `DSGated(isLocked:chipLabel:requiresOnline:isOnlineEnabled:onUpgradeRequested:onOpenAISettings:content:)` — cloud-glyph verschijnt alleen bij requiresOnline && !isOnlineEnabled (vlag uit CreditMeter E14.3 geeft de aanroeper door), naast de Pro-chip top-trailing (inzet gap-1); indicatoren staan buiten de gate-knop zodat ze zelf tikbaar zijn, élke tik op vergrendelde inhoud blijft → onUpgradeRequested. Beide targets bouwen groen, alle tests groen (2 nieuwe smoke-tests).

## 3.8 — Token-verificatie tegen Figma-variabelen
- status: done
- owner: DS
- blockedBy: 3.1
- DoD: beide targets bouwen, tests groen
- Context: werkregel "tokens uit Figma's variabelen, niet uit benaderingen" (besluit Thierry 2026-06-12). 3.1 noteerde al één geïnterpoleerde waarde (neutral-stronger).

get_variable_defs draaien op de Components-pagina (node 11:180), de uitkomst naast
DSColor/DSTypography/DSLayout leggen, afwijkingen corrigeren. Volledige mapping
(Figma-variabele → token) in de Result-regel; geïnterpoleerde of niet-opvraagbare waarden
expliciet markeren.

Notities (DS, bij uitvoering):
- Herstel: de afronding van E03.16 had per abuis deze open Result-placeholder mee-overschreven
  (replace-all); hieronder de echte 3.8-Result.
- De Components-pagina staat in light mode: get_variable_defs geeft daar líghtwaarden — voor de
  dark-tokens is geverifieerd tegen de get_variable_defs-dumps van de dark Stories-frames
  (Email 2611:39442, OTP 2611:39463, First use 4008:7050, Edit-Frame 2 4010:1940,
  Dropzone-Frame 11 4017:1628) plus de Components-dumps van Toggle (61:944) en Search input
  (4016:14177) uit deze sessie.
- Sectie-brede calls (App/Onboarding/Settings/Upgrade Dark) konden niet meer: de Figma
  desktop-app is gesloten (connection refused); de frame-dumps dekken het gebruikte bereik.

**Result:** Geen afwijkingen — alle live geverifieerde waarden zijn 1-op-1 met de codetokens, nul codewijzigingen. Geverifieerd: kleuren background/App #000000, neutral #ffffff0d, action #d5f466, foreground primary #ffffff / subtle #ffffffb2 / muted #ffffff66 / divider #ffffff1a / primary-static-black #111111 / thumb #ffffff, on-action #073c31 (= DSColor); typografie xs 12/16, sm 14.2/20, base 16/24, lg 18, 3xl 25.6/40, 5xl 32.4/48, weights 400/500/600, letterspacing 0, stijlen Labels/Small+Base(+Large), Body/Small+Medium, H1/H3 (= DSTypography; ui="SF Pro"/display="SF Pro Display" via .system — ≥20pt kiest macOS de Display-optical size); spacing gap-0/px/1/1.5/2/2.5/3/3.5/4/5/8/12, radii r-sm/default/md/lg/xl/2xl/4xl/full, borders b-thin 1/b-medium 2, opacity Strong 100. Indirect (renderpixels): background/Card #1c1917, neutral-strongest ≈ wit 15% (dot-grid). Expliciet gemarkeerd, nu niet (her)opvraagbaar: neutral-stronger (geïnterpoleerd, E03.1-besluit), Inset #292524, shadow #190b0859, Projects-palet, gap-0.5/6, r-3xl, lineheight/lg 28, fontsize/2xl 22.8 (H4), opacity Hidden/Disabled/Subtle/Medium (afgeleid uit E03.2-states) — E03.1/3.2-extracties zonder afwijkingssignaal; her-check in één ronde zodra Figma open staat. DSRadius.window (12) is een eigen meetaanname (E03.15), geen Figma-variabele. Beide targets bouwen groen, alle tests groen.

## 3.9 — Button-aanvullingen: full-width + ghost-tekstknop
- status: done
- owner: DS
- blockedBy: 3.2
- DoD: beide targets bouwen, tests groen
- Context: E04.5 legt de gebouwde flows naast de Stories-frames: Onboarding/Email en /OTP tonen Button-instances gestretcht op kolombreedte (360/332) en een ghost-neutral-tekstknop (Resend code, Figma Components Button Type=Ghost Color=Neutral 13:305). DSPrimaryButton/DSNeutralButton huggen alleen; een ghost-tekstknop ontbreekt. (Story toegevoegd door FEAT bij E04.5 — AvatarUI is DS-grens.)

`fullWidth`-parameter op DSPrimaryButton en DSNeutralButton (capsule strekt mee) en DSGhostButton
(tekstknop, states 1-op-1 met het ghostNeutral-gedrag van DSIconButton: default muted zonder bg,
hover bg neutral-stronger + primary, pressed bg neutral-strongest).

**Result:** `fullWidth: Bool = false` op DSPrimaryButton én DSNeutralButton (label-HStack strekt vóór de padding, capsule strekt mee — bestaande call sites ongewijzigd) en DSGhostButton (zelfde maten/parameters als DSPrimaryButton; states 1-op-1 het ghostNeutral-gedrag van DSIconButton: muted → hover bg neutral-stronger + primary → pressed bg neutral-strongest, disabled opacityschaal .25). Beide targets bouwen groen, alle tests groen (1 nieuwe smoke-test).

## 3.10 — Search input-component
- status: done
- owner: DS
- blockedBy: 3.1
- DoD: beide targets bouwen, tests groen
- Context: Figma Components "Search input" (4016:14176, 6 states); gebruikt in de sidebar (App / Sidebar images, instance 224×48). E05.4 gebruikt tijdelijk DSTextField (h40) als stand-in — vervangen zodra deze component er is. (Story toegevoegd door FEAT bij E05.4 — AvatarUI is DS-grens.)

**Result:** DSSearchField in AvatarUI/Components (capsule h48, bg neutral, rand b-thin divider→muted bij focus, px gap-4, zoekicoon 20 muted + gap-2, tekst Body/Medium — placeholder muted/waarde primary; label/helper uit het component bewust buiten scope, geen dark-frame gebruikt ze). Meegelift (bevinding 8c): DSSidebarRow-thumbclip naar continuous corners. Beide targets bouwen groen, alle tests groen (1 nieuwe smoke-test).

## 3.11 — Glass-effect op icon-/toolknoppen
- status: done
- owner: DS
- blockedBy: 3.3
- DoD: beide targets bouwen, tests groen
- Context: visuele-pass-bevinding 4 van Thierry (12 jun, app vs frames): de 48-cirkel-toolknoppen zijn vlak; in Figma (Components → Icon-Only Button, App / Edit) hebben ze een glazige donkere material met subtiele rand/highlight. Figma exposeert het effect niet als variabele — benadering met material + divider-rim + top-highlight, te ijken op de frames.

Publieke DSToolButton (48-cirkel, glass-surface, optionele lime active-ring, 18pt-icoon) en
DSBottomToolbar intern erop; FEAT-callsites (gear) kunnen dan dezelfde component gebruiken
i.p.v. het idioom na te bouwen.

**Result:** DSToolButton publiek in AvatarUI/Components (48-cirkel, 18pt-medium-icoon, lime active-ring b-medium) met DSGlassCircle-surface: ultraThinMaterial + background/neutral + rim-gradient die bovenaan oplicht (primary .18 → .04, b-thin) — benadering, Figma exposeert het materiaal niet als variabele, geijkt op App / Edit; DSBottomToolbar gebruikt hem intern (ToolButton-duplicaat weg). Beide targets bouwen groen, alle tests groen (1 nieuwe smoke-test).

## 3.12 — DSCanvasCard + dot-grid-placeholder
- status: done
- owner: DS
- blockedBy: 3.1
- DoD: beide targets bouwen, tests groen
- Context: visuele-pass-bevindingen 6–7 van Thierry (12 jun). De foto hoort in een afgeronde donkere kaart met marge (App / Edit, App / Image added); zonder ingestelde achtergrond toont de kaart een stippenraster zodat transparante cutout-delen "achtergrond verwijderd" communiceren. NB: het door Thierry genoemde node-id 4031:1876 bestaat niet in het document (alle pagina's doorzocht); bron = de canvas-"Image"-nodes in de feature-frames (bv. 4017:1811, App / Effects), patroon gemeten uit de render.

DSCanvasCard (bg Card, r-4xl, optionele dot-grid-state, inhoud gevuld geclipt) + programmatisch
getekend stippenraster (geen asset): hartafstand 17pt, stip Ø3, kleur wit 15%
(neutral-strongest-waarde) op Background.card — gemeten 1:1 uit de 465×456-render.

**Result:** DSCanvasCard(showsDotGrid:content:) in AvatarUI/Components — bg Card, clip r-4xl, inhoud erbovenop — plus losse publieke DSDotGrid (SwiftUI Canvas, geen asset): stippen Ø3 op 17pt-grid, kleur Background.neutralStrongest, fase spacing/2 (gemeten eerste stip ±(10,6) — fase benaderd, maat/kleur exact). Beide targets bouwen groen, alle tests groen (1 nieuwe smoke-test).

## 3.13 — DSInlineEditLabel (inline edit met hover-affordance)
- status: done
- owner: DS
- blockedBy: 3.1
- DoD: beide targets bouwen, tests groen
- Context: visuele-pass-bevinding 9 van Thierry (12 jun): de Name/Role-inline-edit is buggy (caret over statische tekst). Drie staten gewenst; herbruikbaar voor Name/Role-header (E04.5-fix) en later sidebar-rename.

Eén component, twee varianten (heading/subtitle): rust = pure tekst; hover = badge-affordance
(bg neutral, padding, zachte radius, pointer-cursor); edit = smal inputveld op dezelfde plek
(zelfde typografie/uitlijning, caret in het veld, hover-bg + focus-rand, geen layoutshift) —
Enter/blur bevestigt, Esc annuleert.

**Result:** DSInlineEditLabel in AvatarUI/Components. Contract: `DSInlineEditLabel(_ placeholder: String, text: Binding<String>, variant: .heading|.subtitle)`; drie staten — rust: pure tekst (heading Body/Medium primary, subtitle Body/Small subtle; leeg = placeholder muted); hover: bg neutral, padding gap-2/gap-0.5, r-md continuous, pointer-cursor (NSCursor push/pop); edit: TextField op dezelfde plek met identieke typografie, breedte volgt inhoud via verborgen maattekst + overlay, hover-bg + focus-rand b-thin muted — padding in alle staten gelijk, dus geen layoutshift. Enter/blur committen (getrimd), Esc annuleert (onExitCommand); blur-commit gegate op isEditing zodat Esc niet alsnog commit. Beide targets bouwen groen, alle tests groen (1 nieuwe smoke-test).

## 3.14 — Review-fixes: glass-materiaal, canvas-ratio, inline-edit-breedte
- status: done
- owner: DS
- blockedBy: 3.11, 3.12, 3.13
- DoD: beide targets bouwen, tests groen
- Context: visuele-pass-bevindingen 10–12 van Thierry (12 jun, verse build): (10) DSToolButton oogt vlak — materiaal in lagen met doorschemerende blur; (11) DSCanvasCard hoort vast 1:1 (exportformaat), foto aspect-fill; (12) DSInlineEditLabel-veld kapt tekst af — intrinsieke breedte, meegroeien, nooit clippen.

**Result:** Per punt: (10) DSGlassCircle in lagen — NSVisualEffectView (.hudWindow, blendingMode .withinWindow) als blur-basis zodat content in hetzelfde venster doorschemert (SwiftUI's .ultraThinMaterial blendt op macOS achter het venster en oogde daardoor vlak), daarbovenop neutral-tint, inner-highlight bovenin (primary .10 → clear, top→center) en gradient-rim licht-boven/donker-onder (primary .25 → zwart .35, b-thin); (11) DSCanvasCard dwingt zelf 1:1 af (aspectRatio in de component, exportformaat) — caller levert aspect-fill-inhoud, dot-grid blijft zichtbaar door transparante cutout-delen; integratie: de 465:456-modifiers op de twee Avatar2-call-sites (EditorView, IsolatingCanvas) vervangen door maxWidth/Height 456; (12) DSInlineEditLabel-editveld = ZStack van verborgen maattekst (+ gap-1 caret-marge, bepaalt minimum) en TextField met .fixedSize(horizontal:) (intrinsieke breedte, groeit mee tijdens typen) — gecentreerd, clipt nooit. Beide targets bouwen groen, alle tests groen.

## 3.15 — Review-fixes: active-ring-animatie + concentrische kaartradius
- status: done
- owner: DS
- blockedBy: 3.11, 3.14
- DoD: beide targets bouwen, tests groen
- Context: visuele-pass-bevindingen 16–17 van Thierry (12 jun): (16) de active-ring op de images-tool verspringt/knippert bij het openen van het zijpaneel — de ring is een conditionele view-insert die buiten de layout-animatie valt; (17) de sidebar-hoekradius loopt niet concentrisch met de vensterradius — binnenradius hoort vensterradius − marge te zijn, als regel vastgelegd in DSLayout voor élke kaart-aan-de-rand (panelen!).

**Result:** Per punt: (16) de active-ring in DSToolButton is geen conditionele view-insert meer maar zit permanent in de button-view en schakelt via opacity (+ .animation op isActive, 0,15s easeOut) — hij beweegt nu mee in dezelfde layout-animatie als de toolbar en kan niet meer los hertekenen/knipperen; (17) DSRadius.window (= 12, gemeten benadering — macOS heeft geen publieke API; bij andere ronding is dit de enige knop) + DSRadius.concentric(inset:) = max(window − inset, 0) als vaste regel in DSLayout; integratie: SidebarView exposeert `edgeInset` (gap-1) die ShellView als padding zet én waarmee de kaartradius concentrisch rekent — elke toekomstige kaart-aan-de-rand volgt dezelfde formule. Beide targets bouwen groen, alle tests groen (1 nieuwe unit-test).

## 3.16 — Review-fixes: container-layoutgarantie + inline-edit-conventies
- status: done
- owner: DS
- blockedBy: 3.13, 3.14
- DoD: beide targets bouwen, tests groen — incl. expliciete layouttest op de minimummaat (800×600) met geopend paneel (DoD punt 19)
- Context: visuele-pass-bevindingen 19–21 van Thierry (12 jun): (19) bij beperkte hoogte duwt een geopend paneel de toolbar uit beeld — de foto moet het enige flexibele element zijn, toolbar/paneel nooit afkapbaar; (20) caret staat midden over de placeholder bij een leeg veld — conventie: hint blijft staan in subtle, caret ervóór, eerste toets wist de hint; bestaande waarde volledig selecteren bij focus; (21) buitenklik committet niet — klik in canvas/toolknop/sidebar hoort te committen én de eigen actie uit te voeren.

**Result:** Per punt: (19) DSEditPanelContainer garandeert de layout — foto-slot layoutPriority −1 (krimpt desnoods naar nul), paneel fixedSize verticaal en toolbar fixedSize (nooit afkapbaar of samengedrukt); DoD-test toegevoegd die op 800×600 mét geopend paneel pixel-probet dat foto/paneel niet in de toolbar-zone lekken en het paneel intact is (meting náást de glass-cirkel — de materiaallagen geven ImageRenderer-artefactkleuren; de probe bevestigde overigens dat de container-stack zelf al paste en het zichtbare afkappen uit de verticale centrering in ShellView kwam, FEAT-fix in E04.5). (20) DSInlineEditLabel-editveld is leading uitgelijnd binnen de gecentreerde container: caret staat vóór de hint, de hint (nu Foreground/subtle) blijft staan tot de eerste toetsaanslag, en select-all-bij-focus komt native mee met NSTextField-becomeFirstResponder — geen eigen caret-tekening. (21) Buitenklik committet: lokale NSEvent-monitor zolang het veld actief is; klik buiten het veldframe → commit, het event wordt dóórgegeven zodat canvas/toolknop/sidebar hun eigen actie gewoon uitvoeren (geen view-blokkerende click-catcher); monitor wordt opgeruimd bij commit/cancel/disappear. Handmatige drieklik-test (canvas/toolknop/sidebar) blijft de eindcheck bij de eerstvolgende run. Beide targets bouwen groen, alle tests groen (1 nieuwe layouttest).

## 3.17 — DSInlineEditLabel definitief op NSTextField
- status: done
- owner: DS
- blockedBy: 3.16
- DoD: beide targets bouwen, tests groen; demo-checklist met de vier acceptatiecriteria afgevinkt in de Result, getest met lege én gevulde waarden
- Context: besluit Thierry 2026-06-13 — de eigen caret/focus-implementatie faalde over drie iteraties (bevindingen 9, 12, 20, 21); definitieve herbouw op een echt NSTextField. Acceptatiecriteria: (1) rust = platte tekst, hover-badge alleen op het veld onder de cursor; (2) edit = native veld, caret op tekstpositie, placeholder links van de caret die verdwijnt bij typen, bestaande waarde geselecteerd bij focus; (3) intrinsieke breedte, nooit clippen, header reserveert verticale ruimte; (4) Enter/blur/klik-buiten = commit (aangeklikte control voert z'n actie uit), Esc = annuleer.

**Result:** Herbouwd: het editveld is een echt NSTextField (InlineEditTextField, NSViewRepresentable) — geen eigen caret/focus-code meer; SwiftUI-laag doet alleen nog rust/hover-presentatie en de buitenklik-monitor. Demo-checklist (leeg én gevuld getest):
- [x] 1. Rust = platte tekst zonder chrome; hover-badge per veld via eigen onHover met gebalanceerde cursor-push/pop (kan niet meer blijven hangen op een ander veld) — exclusiviteit visueel nagelopen in render, definitieve muischeck bij de eerstvolgende run.
- [x] 2. Edit = native: caret op tekstpositie en placeholder (muted #ffffff66) links van de caret die bij de eerste toets verdwijnt — standaard NSTextField-placeholdergedrag; bestaande waarde volledig geselecteerd bij focus via window.makeFirstResponder (native select-all). Geverifieerd met lege ("Name"/"Role"-hint) en gevulde waarden.
- [x] 3. Intrinsieke breedte via pure meetfunctie measuredSize (max(tekst, placeholder) + caret-marge; hoogte = vaste Figma-regelhoogte) — unit-getest op leeg/kort/lang (clipt nooit, groeit mee); PortraitHeader reserveert vast 52pt (28+24) zodat Name/Role in elke staat vrij van de canvas-kaart blijven (integratie Avatar2).
- [x] 4. Enter (insertNewline) en Esc (cancelOperation) via de NSTextFieldDelegate — unit-getest op de Coordinator; blur (controlTextDidEndEditing) commit — unit-getest; klik-buiten commit via doorlatende NSEvent-monitor (aangeklikte control voert z'n actie uit), re-entrancy gedekt door de isEditing-guard. De fysieke drieklik (canvas/toolknop/sidebar) blijft de handmatige eindcheck.
Beide targets bouwen groen, alle tests groen (3 nieuwe unit-tests: delegate-routes, blur-commit, meetfunctie).

## 3.18 — DSSidebarRow hover-state, sidebar-padding, inline-edit-polish
- status: done
- owner: DS
- blockedBy: 3.5
- DoD: beide targets bouwen, tests groen
- Context: visuele-pass-punten 22–24 van Thierry (13 jun). (22) Rijen krijgen op hover hetzelfde afgeronde Inset-kleurvlak als de selectie, fade ~100ms, selectie één tint sterker — in het component, niet per gebruiksplek. (23) De binnenpadding van de sidebar-kaart mag ruimer: bewuste afwijking van het Figma-frame (besluit Thierry), één stap omhoog op de DSLayout-schaal. (24) Inline-edit: hover-bg te onzichtbaar op zwart + tekst verspringt bij klik.

**Result:** Per punt: (22) DSSidebarRow heeft nu een component-eigen hover-state: Inset-kleurvlak op r-2xl met 100ms easeOut-fade; selectie is één tint sterker (Inset + neutral-laag erbovenop) zodat de actieve rij herkenbaar blijft terwijl je elders hovert. (23) Sidebar-binnenpadding van gap-3 (12) naar gap-4 (16) rond zoekveld, lijst en add-knop — bewuste afwijking van het Figma-frame op besluit Thierry 2026-06-13, binnen de DSLayout-schaal. (24a) DSInlineEditLabel-hoverachtergrond van neutral naar neutral-stronger. (24b) Alle drie de staten delen exact hetzelfde kader: breedte/hoogte uit de meetfunctie (caret-marge óók in rust gereserveerd), leading-alignment, vaste regelhoogte — alleen achtergrond en rand wisselen, de tekst beweegt geen pixel; de 10×-snelkliktest is de handmatige eindcheck. Beide targets bouwen groen, alle tests groen.

## 3.19 — DSBottomToolbar: accessoire-slots (undo/redo)
- status: ready
- owner: —
- blockedBy: 3.3
- DoD: beide targets bouwen, tests groen
- Context: aangevraagd vanuit E06.2 (frame App / Edit 4008:7340: undo/redo als cirkels ín de toolbar-strip, x344/x400). FEAT plaatst ze tijdelijk als losse DSToolButtons naast de container-toolbar; dit DS-slot integreert ze in DSBottomToolbar (trailing accessoires, zelfde 56-pitch), waarna FEAT de tijdelijke plaatsing verwijdert.

**Result:** _(invullen bij done)_
