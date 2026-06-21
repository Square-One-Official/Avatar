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
- status: ready
- owner: —
- blockedBy: 31.1

Verplaats het Light & color / Adjust-paneel (E24.27, sliders + één-tik-acties) van de zwevende
frame-toolbar naar de onderste toolbar onder de knop **Enhance** (eerste capsule-knop, conform Figma).
Het Adjust-paneel zelf (orthogonale niet-destructieve laag, E24.14) blijft functioneel ongewijzigd —
alléén de ingang verhuist. Verwijder Adjust uit de frame-toolbar. DoD: beide targets + tests groen +
merge + Result + screenshot (Enhance-paneel onderaan).

## 31.3 — AI één-tik-acties → Enhance/onderaan (AI ▾ uit de frame-toolbar) [FEAT]
- status: ready
- owner: —
- blockedBy: 31.2

De AI-appearance-acties (Improve lighting · Colorise · Boost · Restore body, E24.9) bewerken de
*inhoud* van het portret → horen onderaan. Vouw ze in het **Enhance**-paneel (bij de light/color
één-tik-acties) of de `⋯`-overflow; verwijder de `AI ▾`-dropdown uit de frame-toolbar. Pro-/credit-
badges behouden. DoD: beide targets + tests groen + merge + Result + screenshot. **Figma-TODO:** exacte
groepering van de AI-acties binnen Enhance vs. overflow tegen referenties zodra die er zijn.

## 31.4 — Frame-lokale zwevende toolbar = puur frame/scène [DS/FEAT]
- status: ready
- owner: —
- blockedBy: —

Na 31.2/31.3 bevat de zwevende toolbar bij het portret alléén nog **frame/scène/compositie**-controls:
Frame-vorm (Circle/Square, E24.16) · **Background** (besluit 31.5: canvas-gerelateerd → hier) ·
Grid-toggle (E24.26) · **Flip** (besluit: blijft hier) · Auto-frame & center / Crop (stub) /
Fix camera angle (stub). Blijft selectie-gebonden (E28.2) en
zweeft bij het frame. **Geen Figma-referentie** → bouwen in de geest van het hoofddesign met een
duidelijk gemarkeerde **placeholder**; registreer in [[ASSETS.md|plan/ASSETS.md]] (wat, Figma-frame
= n.v.t./nieuw, formaat) + `Figma-TODO` zodat Thierry later het echte design levert. DoD: beide
targets + tests groen + merge + Result + screenshot (frame-toolbar = alléén frame-controls).

## 31.5 — Background → frame-lokale toolbar [FEAT]
- status: ready
- owner: —
- blockedBy: 31.4

Besluit gevallen (Thierry, 2026-06-19): Background is canvas-gerelateerd → in de **frame-lokale
(boven)toolbar**, niet onderaan. Verplaats de Background-ingang (E24.4/E24.31 swatches + upload,
ongewijzigd in functie) naar de frame-toolbar; verwijder 'm uit de onderste set/overflow. Bewuste
afwijking van Figma — documenteren in [[DECISIONS-PENDING.md|plan/DECISIONS-PENDING.md]]. DoD: beide
targets + tests groen + merge + Result + screenshot.

## 31.6 — Face = eigen capsule-knop [FEAT]
- status: ready
- owner: —
- blockedBy: 31.1

Besluit gevallen (Thierry): Face krijgt een eigen top-level knop in de onderste capsule, tussen
`Effects` en `Hair` → **Enhance · Effects · Face · Hair · Shirt · ⋯**. Bewuste afwijking van Figma
(geen top-level Face) — documenteren in [[DECISIONS-PENDING.md|plan/DECISIONS-PENDING.md]]. DoD: beide
targets + tests groen + merge + Result + screenshot.

---

## Definition of Done (epic)

Na 31.1–31.6: de app heeft (1) een persistente onderste capsule (Enhance·Effects·Face·Hair·Shirt·⋯)
en (2) een selectie-gebonden frame-lokale toolbar met uitsluitend frame/scène/compositie-controls
(incl. Background). Adjust + AI-appearance-acties zitten onderaan. Alle besluiten gevallen.
