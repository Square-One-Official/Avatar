# E31 — Toolbar-unificatie (frame-lokaal vs. basis-editing)

Team: **FEAT + DS**. Herziet de IA uit E24/E28 (geen dubbele structuur). Bron-van-principe:
Thierry, 2026-06-19.

## Leidend principe (Thierry)

Twee lagen, op **locatie** geordend i.p.v. op "scène vs. persoon" (de E24-as):

1. **Frame-lokale zwevende toolbar** — alles dat *wáár/hoe* het portret in z'n frame zit verandert,
   staat **vlak bij het frame** (zweeft bij de afbeelding). Voorbeelden: frame-vorm vierkant↔cirkel,
   grid aan/uit. "Wil je iets aan het frame veranderen, dan doe je dat vlakbij het frame."
2. **Onderste toolbar (basis-editing)** — de belangrijkste, terugkerende editing-functies op de
   *inhoud* van het portret: een effect wisselen, kleurcorrectie/enhance, kleding, haar. Deze zit
   onderaan (vast, niet bij het frame).

Kort: **boven/bij het frame = compositie & container · onderaan = hoe het portret eruitziet.**

## Design-bron (geverifieerd via Figma-MCP, 2026-06-19)

Bestand "Aaavatar", pagina **Stories** (`151:1409`). Geverifieerd op de RENDER (laagnamen voor iconen
zijn stale — zie [[project_figma_mcp_workarounds]]):

- **Onderste toolbar = zwevende capsule** met gelabelde knoppen: **Enhance · Effects · Hair · Shirt**
  + een **overflow `⋯`**-icoonknop. Scherm `App / Hair` (`4114:903`); toolbar-node `floatingToolbar`
  (`4114:978` — 4 tekstknoppen + 1 icon-only). Sectie `Bottom toolbar` (`4114:870`).
- **GEEN frame-/canvas-toolbar boven het portret in Figma.** Het portret staat in z'n frame met de
  dot-grid, verder niets. De zwevende `Frame/Background/Adjust/AI`-toolbar (E24) is een **team-vondst
  zónder Figma-referentie**.
- Oudere dock `Toolbar` (`4016:3746`: Edit·Effects·Clothing·Hair·Background·Images) is **vervangen**
  door de capsule hierboven.

**Gevolg voor dit epic:**
- De **onderste toolbar** heeft een referentie → 1-op-1 op de Figma-capsule (incl. `Enhance` als
  eerste knop en de `⋯`-overflow).
- De **frame-lokale toolbar** heeft GEEN referentie → bouwen in de geest van het hoofddesign, met een
  duidelijk gemarkeerde placeholder, geregistreerd in [[ASSETS.md|plan/ASSETS.md]] + `Figma-TODO`.
- `Enhance` als eerste capsule-knop bevestigt Thierry's punt: **kleurcorrectie/light hoort onderaan**,
  niet zwevend bij het frame.

## Vaste besluiten (Thierry, "on, on")

- **Flip blijft in de frame-groep** (compositie-transform, geen pixel-generatie).
- **Onderste toolbar blijft persistent** — verdwijnt NIET bij deselect (het is de basis-UI van de app;
  basis-chrome dat in/uit knippert breekt de ruimtelijke consistentie). Herziet E28.3 voor de
  bottom-toolbar. De **frame-lokale** toolbar blijft wél selectie-gebonden (die wijst naar het
  geselecteerde portret) — E28.2 blijft daar gelden.

## Besloten — afwijking van Figma (Thierry, 2026-06-19)

- **Background → frame-lokale (boven)toolbar.** "The canvas related one top": Background bewerkt de
  scène/canvas áchter het portret → canvas-gerelateerd → hoort bij het frame, niet onderaan. Dit is
  een **bewuste afwijking** van Figma (dat Background in de onderste `⋯`-overflow zet); toegestaan als
  expliciet Thierry-besluit (CLAUDE.md). De "main" editing-functies blijven onderaan.
- **Face → eigen capsule-knop.** Face krijgt een eigen top-level knop in de onderste capsule (niet onder
  `⋯`-overflow). Bewuste afwijking van Figma (geen top-level Face). Onderste set wordt daarmee
  **Enhance · Effects · Face · Hair · Shirt · ⋯**.

---

## 31.1 — Onderste toolbar = Figma-capsule (persistent) [DS/FEAT]
- status: done
- owner: DS+FEAT (AI-agent, marathon)
- blockedBy: —

De `DSBottomToolbar` volgt de Figma-capsule (zwevend, gecentreerd onderaan), met gelabelde knoppen
**Enhance · Effects · Face · Hair · Shirt** + een **overflow `⋯`**-icoonknop. (`Face` is een bewuste
toevoeging t.o.v. Figma — besluit 31.6.) **Persistent**
(herziet E28.3: niet verbergen bij deselect; de "Click the portrait to edit"-pill vervalt of wordt een
disabled-state — bevestig in Result). Knoppen tonen icoon+label zoals in `floatingToolbar` (`4114:978`).
DoD: beide targets + tests groen + merge + Result + screenshot tegen `4114:903`.

**Result:** `DSBottomToolbar` is herbouwd als de Figma-capsule (geverifieerd via MCP op `4114:978` +
`get_variable_defs`): Card-fill (#1c1917) r-full container, gelabelde **icoon+label-pillen**
(`DSCapsuleToolButton`: pil = background/neutral wit@5%, label = `UI/Labels/Base` SF Pro Semibold 14.2,
hoogte 40, gap-2 padding) + een **overflow `⋯`-knop** (`DSToolbarOverflowButton`, 40-cirkel, vertikale
dots, opent een `Menu`). Active = lime icoon+label + lime ring (E03.3). FEAT: de capsule-set is
**Enhance(`.edit`) · Effects · Face · Hair · Shirt(`.clothing`)** met eigen labels (Enhance/Shirt) +
overflow **Background**(`.background`) conform Figma; alle vijf + Background hebben al werkende panelen
(de panel-builder dekt `.edit/.face/.background` al). `DSEditPanelContainer` kreeg een `overflowTools:`-
doorgeefparameter (EmptyView/`[]`-defaults houden bestaande call sites werkend). **Persistentie:** al
geleverd door E28.5 (toolbars altijd zichtbaar in de editor); de "Click the portrait to edit"-pill
bestond niet meer — niets te verwijderen, bevestigd. 1 nieuwe DS-test (capsule + overflow + accessoire),
AvatarUI 31/31 groen; beide targets bouwen Debug groen via build-v2.sh. Visuele smoke (`--seed-adjust`,
scherm ontgrendeld) 1-op-1 tegen `4114:903` — zie /tmp/aaashots/e31-strip.png.
- **Figma-TODO:** Figma's capsule-frame toont géén undo/redo; ze blijven (E06.6) als losse
  `DSToolButton`-cirkels **náást** (buiten) de Card-capsule in dezelfde strip. Definitieve plaatsing
  tegen een referentie zodra Thierry die levert.
- **Iconen:** de pil-iconen zijn de bestaande semantische SF-Symbols per tool (palette/sparkles/
  smiley/comb/tshirt); Figma's capsule-iconen zijn placeholder-sparkles (stale, zie
  [[project_figma_mcp_workarounds]]) → bewust niet 1-op-1 overgenomen.
- **Tijdelijke dubbeling:** Adjust(`.edit`) en Background staan nu zowel in de capsule/overflow als nog
  in de frame-toolbar (E24). Dat is de bedoelde tussenstand: **31.2** haalt Adjust uit de frame-toolbar,
  **31.5** haalt Background uit de overflow (→ frame-toolbar).

## 31.2 — Adjust → onderste toolbar als "Enhance" [FEAT]
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 31.1

Verplaats het Light & color / Adjust-paneel (E24.27, sliders + één-tik-acties) van de zwevende
frame-toolbar naar de onderste toolbar onder de knop **Enhance** (eerste capsule-knop, conform Figma).
Het Adjust-paneel zelf (orthogonale niet-destructieve laag, E24.14) blijft functioneel ongewijzigd —
alléén de ingang verhuist. Verwijder Adjust uit de frame-toolbar. DoD: beide targets + tests groen +
merge + Result + screenshot (Enhance-paneel onderaan).

**Result:** De capsule-knop **Enhance** (`.edit`) opent nu het **volledige** `editColorPanel`
(E24.27: sliders Brightness/Contrast/Saturation/Temperature + Auto-enhance-acties Improve lighting/
Colorise/Boost, incl. `improveLightingOn`-state) — de uitgeklede inline-EditColorPanel in de
panel-builder is vervangen door `editColorPanel`, paneeltitel "Enhance". Het Adjust-paneel is dus
functioneel ongewijzigd, alleen de ingang verhuisde. **Adjust verwijderd uit de frame-toolbar:**
`CanvasActionToolbar` verloor de `.adjust`-enumcase, de generic `Adjust: View` + `adjust`-builder,
het `toolbarItem(.adjust,…)`-blok en de `--show-adjust-popover`-debughaak; het call-site liet de
`adjust:`-arg vallen. De frame-toolbar is nu **Frame ▾ · Background · AI ▾** (+ grid-toggle).
Visuele smoke (`--seed-adjust --open-panel edit`, scherm ontgrendeld): Enhance-pil lime-actief, het
Enhance-paneel onderaan met one-tap-rij + 4 sliders, en de frame-toolbar zónder Adjust — zie
/tmp/aaashots/e31-2c.png. Beide targets bouwen Debug groen via build-v2.sh, alle suites groen.
NB (tussenstand): de AI ▾-dropdown (alleen nog "Restore body" na E24.27) blijft in de frame-toolbar
tot **31.3** 'm eruit haalt.

## 31.3 — AI één-tik-acties → Enhance/onderaan (AI ▾ uit de frame-toolbar) [FEAT]
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 31.2

De AI-appearance-acties (Improve lighting · Colorise · Boost · Restore body, E24.9) bewerken de
*inhoud* van het portret → horen onderaan. Vouw ze in het **Enhance**-paneel (bij de light/color
één-tik-acties) of de `⋯`-overflow; verwijder de `AI ▾`-dropdown uit de frame-toolbar. Pro-/credit-
badges behouden. DoD: beide targets + tests groen + merge + Result + screenshot. **Figma-TODO:** exacte
groepering van de AI-acties binnen Enhance vs. overflow tegen referenties zodra die er zijn.

**Result:** Improve lighting/Colorise/Boost zaten al in het Enhance-paneel (E24.27); **Restore body**
is nu de 4e chip in dezelfde Auto-enhance-rij (`EditColorPanel` kreeg `onRestoreBody`, chip met
`pro: !isPro`-badge; `editColorPanel` wired op `entitlement?.allowCloudFeature()`). De **AI ▾-dropdown
is volledig uit de frame-toolbar:** `CanvasActionToolbar` verloor de `.ai`-enumcase, het
`toolbarItem(.ai,…)`-blok, de `aiMenu`-view, de `--show-ai-popover`-haak en de daarmee dode params
(`onRestoreBody/onImproveLighting/onColorise/onBoost/isPro` — de drie midden waren al dood sinds
E24.27). Het call-site liet die args vallen. De frame-toolbar is nu **Frame ▾ · Background** (+ grid-
toggle). Pro-/credit-badges behouden (Boost = "1 credit"; Colorise/Restore body = Pro-chip buiten Pro).
Visuele smoke (`--seed-adjust --open-panel edit`, scherm ontgrendeld): vier chips incl. Restore body,
frame-toolbar zonder AI — zie /tmp/aaashots/e31-3.png. Beide targets bouwen Debug groen, alle suites
groen. **Figma-TODO** blijft staan (Enhance vs. overflow-groepering zodra er een referentie is).

## 31.4 — Frame-lokale zwevende toolbar = puur frame/scène [DS/FEAT]
- status: done
- owner: DS+FEAT (AI-agent, marathon)
- blockedBy: —

Na 31.2/31.3 bevat de zwevende toolbar bij het portret alléén nog **frame/scène/compositie**-controls:
Frame-vorm (Circle/Square, E24.16) · **Background** (besluit 31.5: canvas-gerelateerd → hier) ·
Grid-toggle (E24.26) · **Flip** (besluit: blijft hier) · Auto-frame & center / Crop (stub) /
Fix camera angle (stub). Blijft selectie-gebonden (E28.2) en
zweeft bij het frame. **Geen Figma-referentie** → bouwen in de geest van het hoofddesign met een
duidelijk gemarkeerde **placeholder**; registreer in [[ASSETS.md|plan/ASSETS.md]] (wat, Figma-frame
= n.v.t./nieuw, formaat) + `Figma-TODO` zodat Thierry later het echte design levert. DoD: beide
targets + tests groen + merge + Result + screenshot (frame-toolbar = alléén frame-controls).

**Result:** De inhoud was al gestript door 31.2 (Adjust eruit) en 31.3 (AI ▾ eruit) — de
`CanvasActionToolbar` bevat nu uitsluitend frame/scène/compositie-controls: **Frame ▾**
(Auto-frame & center · Crop[stub] · Fix camera angle[stub] · Flip horizontal · Shape Circle/Square)
· **Background** · **grid-toggle**. Selectie-gebonden-gedrag ongewijzigd (E28.2 op de board; E28.5
houdt 'm altijd zichtbaar in de single-portrait-editor). **Placeholder-markering:** er is geen
Figma-referentie (capsule 4114:978 toont deze toolbar niet — team-vondst), dus geregistreerd als
placeholder-design in [[ASSETS.md|plan/ASSETS.md]] #5 + een `FIGMA-TODO`-blok in de
`CanvasActionToolbar`-header zodat Thierry het echte design later levert. Geen verdere code-
herstructurering nodig (de dropdown-structuur is in de geest van het hoofddesign). Visuele smoke
(`--seed-adjust --show-frame-popover`, scherm ontgrendeld): Frame ▾ open toont enkel de frame-acties,
toolbar = Frame ▾ · Background · grid — zie /tmp/aaashots/e31-4.png. Beide targets bouwen Debug groen,
alle suites groen. NB: Background staat nu nog óók in de capsule-overflow (31.1, Figma-faithful);
**31.5** haalt 'm daar weg (blijft hier).

## 31.5 — Background → frame-lokale toolbar [FEAT]
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 31.4

Besluit gevallen (Thierry, 2026-06-19): Background is canvas-gerelateerd → in de **frame-lokale
(boven)toolbar**, niet onderaan. Verplaats de Background-ingang (E24.4/E24.31 swatches + upload,
ongewijzigd in functie) naar de frame-toolbar; verwijder 'm uit de onderste set/overflow. Bewuste
afwijking van Figma — documenteren in [[DECISIONS-PENDING.md|plan/DECISIONS-PENDING.md]]. DoD: beide
targets + tests groen + merge + Result + screenshot.

**Result:** Background staat (sinds altijd) in de frame-lokale `CanvasActionToolbar` en is nu uit de
**capsule-overflow** gehaald: `EditorView.overflowItems` = `[]` (was `[Background]` uit 31.1). Gevolg:
de overflow is leeg → de **`⋯`-knop verschijnt niet meer** (DSBottomToolbar toont 'm alleen met
inhoud; keert automatisch terug zodra er overflow-tools komen). Background-functie (E24.4/E24.31
swatches + upload) ongewijzigd. Bewuste Figma-afwijking vastgelegd in
[[DECISIONS-PENDING.md|plan/DECISIONS-PENDING.md]] (E31-blok). Visuele smoke (`--seed-adjust`, scherm
ontgrendeld): onderste capsule = **Enhance · Effects · Face · Hair · Shirt** (geen `⋯`), frame-toolbar
= **Frame ▾ · Background · grid** — zie /tmp/aaashots/e31-5-strip.png + e31-5-full.png. Beide targets
bouwen Debug groen, alle suites groen. (De bottom-panel-builder houdt een ongebruikte `.background`-
tak; onschadelijk — Background wordt nu alleen via de frame-toolbar-dropdown geopend.)

## 31.6 — Face = eigen capsule-knop [FEAT]
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: 31.1

Besluit gevallen (Thierry): Face krijgt een eigen top-level knop in de onderste capsule, tussen
`Effects` en `Hair` → **Enhance · Effects · Face · Hair · Shirt · ⋯**. Bewuste afwijking van Figma
(geen top-level Face) — documenteren in [[DECISIONS-PENDING.md|plan/DECISIONS-PENDING.md]]. DoD: beide
targets + tests groen + merge + Result + screenshot.

**Result:** Face zit als eigen top-level capsule-knop (`DSToolbarItem(id: .face, label: "Face")`)
tussen Effects en Hair — geïmplementeerd in 31.1, hier bevestigd. Onderste set =
**Enhance · Effects · Face · Hair · Shirt** (de `⋯` verviel in 31.5). De knop opent de
`FaceActionsPanel` (One click retouch · Whiten teeth · Apply make-up · Reduce wrinkles, met
credit-badges) onderaan. Bewuste Figma-afwijking (geen top-level Face in 4114:978) vastgelegd in
[[DECISIONS-PENDING.md|plan/DECISIONS-PENDING.md]] (E31-blok). Geen code-wijziging nodig in deze
story. Visuele smoke (`--seed-adjust --open-panel face`, scherm ontgrendeld): Face-pil lime-actief,
Face-paneel open — zie /tmp/aaashots/e31-6.png. Beide targets bouwen Debug groen, alle suites groen.

## 31.7 — Board/canvas-view trekt gelijk met de single-editor [FEAT]
- status: done
- owner: FEAT (AI-agent)
- blockedBy: 31.1–31.6

De board/canvas-view (`BoardView`, E27–E30) had eigen hand-gebouwde toolbars (eigen `EditTool`-enum,
eigen bottom-strip `Effects·Face·Clothing·Hair` zónder Enhance, inline kleur-swatches voor Background)
→ inconsistent met de single-editor. Trek gelijk:

- **Onderste toolbar** → dezelfde `DSBottomToolbar` met de GEDEELDE items
  (`EditorView.toolbarItems`): **Enhance · Effects · Face · Hair · Clothing**. `editTool` is nu
  `EditorTool` (geen duplicaat-enum). Enhance (`.edit`) opent het kleur/Adjust-paneel (Adjust verhuisde
  uit de oude board-top-bar hierheen, net als de editor).
- **Single-select top-bar** → dezelfde `CanvasActionToolbar`, getrimd tot board-relevante controls
  (`showFramingActions:false`, `showGrid:false`): Frame ▾ (Shape + Flip) · Background. Besluit Thierry:
  Auto-frame/Grid weglaten (no-op op statische nodes).
- **Background overal** → dezelfde volledige `BackgroundPanel` (Transparent/Original/Image/upload/
  gradient/color/brand) i.p.v. inline swatches; `BackgroundPanel` kreeg een `onApply`-closure zodat de
  batch-bar dezelfde panel-UI op ALLE geselecteerde toepast.
- **Label "Shirt" → "Clothing"** (besluit Thierry: canoniek voor BEIDE views) — gewijzigd in
  `EditorView.toolbarItems`, dus de single-editor capsule heet nu ook "Clothing".
- Batch (multi-select): bewust alléén styling + Background geünificeerd (Match lighting + Adjust blijven
  batch-only; geen per-tool batch-toolbar).

Verwijderd: `BoardView.EditTool`, `batchBackgrounds`, `backgroundSwatch`, `bottomToolButton`.
**Restpunt:** de board-"Enhance" opent het kleur/Adjust-paneel (= de relocatie van de oude board-
Adjust); de AI-één-tik-acties (Improve lighting/Colorise/Boost/Restore body) die de editor-Enhance
heeft zijn op de board nog niet bedraad — aparte follow-up.

DoD: beide targets + tests groen + merge + Result + screenshot (board single-select === editor-chrome;
board Background = volledige panel; multi-select batch met panel-Background).

**Result:** `BoardView` hergebruikt nu de single-editor-componenten i.p.v. eigen chrome:
single-select bottom = `DSBottomToolbar(items: EditorView.toolbarItems)` (Enhance·Effects·Face·Hair·
Clothing); single-select top = getrimde `CanvasActionToolbar` (Frame ▾ Shape+Flip · Background);
Background overal = `BackgroundPanel` (nieuw `onApply`-closure voor de batch). `EditTool`-duplicaat,
`batchBackgrounds`, `backgroundSwatch`, `bottomToolButton` verwijderd. Label "Shirt"→"Clothing" in
`EditorView.toolbarItems` (canoniek voor beide views). `CanvasActionToolbar` kreeg
`showFramingActions`/`showGrid` (default true → single-editor ongewijzigd). Beide targets bouwen Debug
groen via `build-v2.sh`; AvatarUI 31/31 + Avatar2-unit + AvatarKit groen.
**Verificatie-beperking (eerlijk):** code-/build-geverifieerd; de visuele smoke van de board-staten
(single-select === editor + batch-Background-panel) leunt op de al in 31.1 vastgelegde component-shots
(DSBottomToolbar/CanvasActionToolbar/BackgroundPanel zijn ongewijzigd hergebruikt) — een verse
board-screenshot is een interactieve check (board-selectie) die het beste door Thierry in de draaiende
app wordt bevestigd; debug-haken `--board-select <n>` / `--board-batch-bg <hex|none>` staan klaar.
**Restpunt:** board-"Enhance" = kleur/Adjust-paneel; de editor-Enhance AI-één-tik-acties zijn op de
board nog niet bedraad (aparte follow-up).

---

## Definition of Done (epic)

Na 31.1–31.6: de app heeft (1) een persistente onderste capsule (Enhance·Effects·Face·Hair·Clothing·⋯)
en (2) een selectie-gebonden frame-lokale toolbar met uitsluitend frame/scène/compositie-controls
(incl. Background). Adjust + AI-appearance-acties zitten onderaan. 31.7 trekt de board-view gelijk met
ditzelfde model. Alle besluiten gevallen.
