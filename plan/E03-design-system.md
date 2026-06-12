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
