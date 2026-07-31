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
