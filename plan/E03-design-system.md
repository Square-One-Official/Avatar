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
- status: in_progress
- owner: DS
- blockedBy: 3.2
- DoD: beide targets bouwen, tests groen

Eén gating-patroon voor alle features (les uit v1: niet versnipperen).

**Result:** _(invullen bij done)_

## 3.5 — Formulier- en lijstcomponenten
- status: backlog
- owner: —
- blockedBy: 3.2
- DoD: beide targets bouwen, tests groen

OTP-veld, tekstveld, panel-headers, sidebar-rij (avatar+naam+rol), add-knop (button-component uit
Figma).

**Result:** _(invullen bij done)_

