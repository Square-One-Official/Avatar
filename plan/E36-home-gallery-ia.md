# E36 — Home & gallery-IA (unified overzicht + Banners als grid)

Team: **FEAT** (+ DS waar een nieuw AvatarUI-component nodig is)

Voortgekomen uit feedback (Thierry, 2026-06-26): nu we Banners hebben moet de **Home** een
echt overzicht van álle items worden, en de **Banners-sectie** moet zich net als Portraits
gedragen (een overzicht van je gemaakte banners), niet een gradient-generator. De gradient-
quick-create vervalt; in plaats daarvan een **empty state** met "Make banner" + CMS-presets.

Samenhang: dit epic herziet de IA en gallery-schermen. De editor zelf = **E37 (Banner
Studio)**, de procedurale shaders = **E38**, CMS-presets = **E39**, banner-als-portret-
achtergrond = **E40**. E35 (banner-bibliotheek, "geen canvas") wordt hierdoor uitgebreid; de
gradient-presetrij uit 35.3 wordt vervangen (zie 36.2).

**Design-uitgangspunt (geldt voor alle stories):** géén 1-op-1 Figma-referentie — deze schermen
bestaan nog niet in Figma. Bouwen **in de geest van het design system**: uitsluitend AvatarUI-
tokens/-componenten (`DSColor`, `DSSpacing`, `DSRadius`, `DSTypography`, `DSMotion`,
`DSThumbnailCard`, `DSCanvasCard`, empty-state-patroon). Nieuwe componenten horen in `AvatarUI/`
(DS-story) als ze herbruikbaar zijn, anders feature-lokaal "in DS-stijl". Referentie-patronen
(géén kopie — inspiratie tegen AI-slop):
- Unified home met "Recent items" hero + secties: [Fabric](https://mobbin.com/screens/4417cfa4-28b4-4db7-8ba7-3170b2e9cfb5), [Edits](https://mobbin.com/screens/95d5f3b7-3390-4636-97e3-86241d01e167).
- Projecten-grid met thumbnails + context-acties: [Canva](https://mobbin.com/screens/55975230-ad04-4689-83e9-81363662bc5d), [Procreate Pocket](https://mobbin.com/screens/bfdbd700-03ad-4746-a35a-1b844f5dba83), [Unfold](https://mobbin.com/screens/c89383b7-fa06-4ae0-ac97-f728b7d9cba3).

---

## 36.1 — BannersGalleryView → Portraits-stijl grid
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT

**Result:** [BannersGalleryView](Avatar2/Features/Banners/BannersGalleryView.swift) herbouwd als
Portraits-spiegel: zwevende, gemeten header (titel + banner-telling + primaire **"Make banner"**)
boven een `LazyVGrid` van WIJDE (3:1) `BannerGridTile`s met hover-rand (DS-`Action.primary`) en
naam-label. **Gradient-snel-maker verwijderd** (`presetsRow`/`addGradient`/`BackgroundKit`/
`BannerCompositor`-gebruik weg). Rechtsklik = Rename/**Duplicate**/Delete. "Make banner" opent
voorlopig de upload (TODO E37.2 → Banner Studio); tegel-klik is een no-op-placeholder (TODO
E37.2). Empty-state-placeholder in DS-stijl tot E36.2. Volledige DoD groen.

Herbouw [BannersGalleryView](Avatar2/Features/Banners/BannersGalleryView.swift) zodat ze de
Portraits-gallery spiegelt i.p.v. de huidige upload/gradient-pagina:
- Drijvende header ("Banners" + primaire "Make banner"-knop) zoals
  [PortraitsGalleryView](Avatar2/Features/Portraits/PortraitsGalleryView.swift) (gemeten header-
  hoogte via preference key).
- `LazyVGrid` van **wijde** banner-tegels (aspect 3:1, `DSThumbnailCard`-stijl, geclipte hoeken,
  hover/selectie-state, naam-label). Tegel-min/max afgestemd op de wijde verhouding (niet de
  vierkante portret-tegel). Thumbnail uit `Banner2.imageData` (later: gerenderde `BannerDoc`-
  preview, E37).
- **Verwijder** de "Start from a gradient"-presetrij en `addGradient(...)` (gradients zijn
  overbodig). Upload blijft als secundaire actie (in de "Make banner"-flow / overflow, niet als
  losse knop bovenaan).
- Rechtsklik-contextmenu: Rename / Duplicate / Delete (spiegelt portret-tegel).
- Klik op een tegel → opent de Banner Studio (E37; tot 37.2 bestaat: open een tijdelijke
  placeholder-detail of no-op met TODO-marker — niet blokkerend).
- **Geen Figma-ref** — DS-tokens; patroon = Portraits-gallery.
- DoD: beide targets bouwen, tests groen, Result-regel.

## 36.2 — Banners empty-state ("Make banner" + presets)
- status: done
- owner: FEAT (2026-06-26)

**Result:** `BannersEmptyState` (in [BannersGalleryView](Avatar2/Features/Banners/BannersGalleryView.swift)) — kop + "Make banner" (→ lege Studio) + een raster **preset-kaarten** (wijde fill-previews; klik → nieuw `BannerDoc` met die laagstack + Studio). Lokale fallback-presets nu; CMS-presets vervangen/vullen aan in E39.2. DoD groen.
- team: FEAT (+ DS indien nieuw empty-state-component)
- blockedBy: 36.1

Empty-state wanneer `banners.isEmpty`, in de geest van `FirstUseEmptyState` (Portraits) maar
banner-specifiek:
- Korte kop + sub ("Maak je eerste banner") + prominente **"Make banner"** primaire knop
  (→ E37 Studio, lege canvas).
- Daaronder een rij/raster **presets** (wijde preview-kaarten) waaruit je kunt kiezen → opent de
  Studio voorgevuld. Presets komen uit de CMS (**E39**); tot 39.x: een lokale fallback-set
  (markeer als placeholder in `plan/ASSETS.md`) zodat interactie/animatie volledig af is.
- Geen gradient-knoppen meer.
- **Geen Figma-ref** — DS-tokens; patroon = empty-state + template-gallery
  ([GoDaddy Studio](https://mobbin.com/screens/d9df013b-3e5b-4a3a-a12c-0054b26868f4),
  [Photoroom "start from blank/preset"](https://mobbin.com/screens/49af6b73-b3a8-49f8-8e72-1b10a8d93c4e)).
- DoD: beide targets bouwen, tests groen, Result-regel.

## 36.3 — HomeView → unified overzicht van alle items
- status: done
- owner: FEAT (2026-06-26)

**Result:** [HomeView](Avatar2/Features/Shell/HomeView.swift) toont nu naast de portret-sectie (Recent = grote featured + Earlier-grid, al aanwezig) een **Banners-sectie** onderaan: kop + "See all" (→ showBanners) + een horizontale rij recente banner-kaarten (BannerDoc-previews → openBannerStudio), of een "Make a banner"-CTA als er nog geen zijn. Unified overzicht van álle items. DoD groen.
- team: FEAT
- blockedBy: 36.1

Herzie [HomeView](Avatar2/Features/Shell/HomeView.swift) tot één overzicht van álle items:
- **Portraits-sectie bovenaan**: meest recente portret als grote "hero"-kaart, de overige recente
  portretten kleiner ernaast/eronder (zoals nu het "Recent"/"Earlier"-idee, maar visueel
  duidelijker: 1 groot + N klein). Klik → editor (bestaande `openPortrait` + hero-morph).
- **Banners-sectie daaronder**: rij/raster recent gemaakte banners (kleinere wijde kaarten) +
  een "See all"/sectie-kop → `showBanners()`. Klik → Banner Studio (E37).
- (Optioneel, indien E39 klaar) een "Start a banner"-presetrij onderaan.
- Empty-gedrag: als beide leeg → bestaande first-use; als alleen banners leeg → toon enkel
  Portraits-sectie + een subtiele "Make a banner"-CTA.
- Behoud de zwevende "Upload portrait"-knop / pas aan tot een nette primaire actie.
- **Geen Figma-ref** — DS-tokens; patroon = unified home (Fabric/Edits, zie kop).
- DoD: beide targets bouwen, tests groen, Result-regel.

## 36.4 — Left-nav + sectie-routing afstemmen
- status: done
- owner: FEAT (2026-06-26)

**Result:** Geverifieerd — `ShellModel`-secties (home/portraits/banners/editor) + de left-nav-"Banners"-rij (→ `showBanners()`, correct gehighlight) kloppen; "Make banner" komt consistent in de Studio uit vanuit de gallery-header, de home-CTA én de empty-state (E36.1/36.2/36.3). Geen codewijziging nodig (Thierry's nav-refactor blijft leidend); v2-main bouwt groen. Geen aparte build.
- team: FEAT
- blockedBy: 36.1

Kleine afronding van navigatie nu Home een overzicht is:
- Controleer dat `ShellModel`-secties (home/portraits/banners/editor) + left-nav-rijen kloppen;
  "Banners" blijft onder Portraits. (Let op: `LeftNavView.swift` wordt parallel bewerkt door een
  andere sessie — raak alleen aan wat nodig is en stage per pad.)
- "Make banner" vanuit nav/home/empty-state komt consistent in de Studio (E37) uit.
- **Geen Figma-ref** — DS-tokens.
- DoD: beide targets bouwen, tests groen, Result-regel.

## 36.5 — Bestandsnaam als default-portretnaam
- status: done
- owner: FEAT (2026-07-02)
- team: FEAT
- blockedBy: —

**Result:** `ShellModel.defaultPortraitName(from:)` — bestandsnaam zonder extensie,
gehumaniseerd (`-`/`_` → spatie, dubbele separators samengevouwen) — reist mee van
`importImage(from:)` via `runCutout(defaultName:)` tot `persist(name:)` →
`Portrait2(name:)`; open-panel én file-drops krijgen dus een zinvolle naam, naamloze
`Data`-drops blijven leeg. "New folder…" uit het portret-contextmenu
([PortraitContextMenu](Avatar2/Features/Portraits/PortraitContextMenu.swift)) maakt geen
stille "Untitled folder N" meer maar vraagt eerst een naam (zelfde alert-prompt als de
left-nav-flow; lege naam = annuleren). 4 nieuwe naam-tests in `ShellModelTests`. DoD groen.

**Vervolg (2026-09-02, Thierry):** "als de naam van de persoon in de bestandsnaam staat,
die al vullen" — `defaultPortraitName(from:)` delegeert nu aan `PortraitNameGuess`
([PortraitNameGuess.swift](Avatar2/Features/Shell/PortraitNameGuess.swift)): tokens met
cijfers en ruiswoorden (img/dsc/headshot/copy/final/linkedin/team/…) vallen weg,
tussenvoegsels (van/de/der/von/…) blijven alleen tússen naamdelen, camelCase splitst na
≥ 3 tekens, all-lower/all-caps wordt gekapitaliseerd. `Thierry_Emmery_headshot_2024.jpg`
→ "Thierry Emmery"; `IMG_4821.HEIC` → "" (Name-veld toont "Add name" i.p.v. "IMG 4821").
Gedragswijziging t.o.v. de eerste versie: een bestandsnaam zónder herkenbare naam levert
geen naam meer op. 4 tests in `ShellModelTests` vervangen (23/23 groen).

**Vervolg 2 (2026-09-02, Thierry: "kunnen we slimmer naam herkennen?"):**
[PortraitNameResolver.swift](Avatar2/Features/Shell/PortraitNameResolver.swift) — drie lagen:
(1) beeld-metadata (IPTC ObjectName/Caption/Keywords, TIFF ImageDescription, PNG Title,
Exif UserComment); (2) on-device model via Foundation Models (macOS 26 + Apple Intelligence
aan, weak-linked; guided generation, antwoord gevalideerd tegen de input — geen verzonnen
namen; 4s-timeout); (3) heuristiek `PortraitNameGuess` (bestandsnaam + titel-velden) als
fallback. De resolutie loopt parallel aan de cutout en wordt pas bij `persist` afgewacht;
batch-tegels tonen de heuristiek-naam als placeholder. Data-drops (Photos/browser) krijgen
nu ook een naam als de metadata er een bevat. 8 tests in `PortraitNameResolverTests`
(model uit; deterministisch). Laag 2 is nog niet live gevalideerd — Apple Intelligence staat
op de dev-Mac uit; NLTagger afgewezen als fallback (NL geen name-model, EN te wisselvallig).

**Vervolg 3 (2026-09-02, Thierry: "B, volledig offline" — geen Apple Intelligence):**
[FirstNameLexicon.swift](Avatar2/Features/Shell/FirstNameLexicon.swift) — gebundeld lexicon van
2200 voornamen (NL/Fries/EN/DE/FR/ES/IT/PT/PL/Scandinavisch/TR/Arabisch/Hindoestaans/Oost-Aziatisch,
accent-gevouwen). `PortraitNameGuess.refine`: mét voornaam is die het anker (alles ervóór valt af,
behalve het "Achternaam Voornaam"-patroon met precies twee delen; ná de achternaam stopt de naam bij
het eerste gewone woord); zónder voornaam beslist een NLTagger-woordenboekcheck (EN, `.otherWord`)
— alleen gewone woorden ("man beard", "square one") → geen naam, een onbekend woord ("looijen") blijft
achternaam. Telwoorden zijn ruis. Gedragswijziging: `p1-man-beard.png` → "" (was "Man Beard").
Laag 2 (on-device model) blijft bestaan voor Macs mét Apple Intelligence. 33/33 + 8/8 tests groen.

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding B5).
**Wat:** import gooit de bron-bestandsnaam weg — `ShellModel`'s import-pad geeft
alleen het gedecodeerde `CGImage` door aan `persist(cutout:original:)`, die een
`Portrait2(name: "")` aanmaakt. Terwijl de bron-URL (bv. `p1-man-beard.png`) op dat
moment gewoon beschikbaar is. Dit is de root cause dat alles "Untitled" heet — op
Home, in alle lenzen, in de breadcrumb en het lege Name-veld in de editor. Voor de
HR-usecase ("vind portret van collega X terug") is dit een kern-gap. Los daarvan
maakt "New folder…" uit het portret-contextmenu (`PortraitContextMenu.swift:108-113`)
stil een "Untitled folder N" — de left-nav-flow vraagt wél een naam
(`LeftNavView.swift:151-155`).
**Voorstel:** geef de bron-`url` door tot in `persist` en zet
`name = url.deletingPathExtension().lastPathComponent` (gehumaniseerd: `-`/`_` →
spatie); dropped `Data` zonder URL blijft leeg. Hergebruik dezelfde naam-prompt van
de left-nav-flow voor "New folder…" uit het contextmenu.
**DoD:** beide targets bouwen; een import via bestandsdialoog krijgt een
zinvolle default-naam i.p.v. "Untitled"; "New folder…" vraagt altijd een naam;
tests groen; Result-regel.

## 36.6 — Zoekveld in Portraits (backlog)
- status: backlog
- team: FEAT
- blockedBy: 36.5

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding B5).
**Wat:** er is nul `searchable`-gebruik in Shell/Portraits — terugvinden leunt
volledig op namen (die vóór 36.5 niet eens gezet werden).
**Voorstel:** een zoekveld in de Portraits-header dat filtert op `Portrait2.name`
(en eventueel later op rol/team-veld).
**DoD:** beide targets bouwen; typen in het zoekveld filtert de actieve lens
live; tests groen; Result-regel.
