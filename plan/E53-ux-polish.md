# E53 — UX-polish n.a.v. UX-audit 2026-07-02

Team: **FEAT + DS**

Bron: `plan/AUDIT-UX-2026-07-02.md` (33 bevindingen: 8×P0, 15×P1, 10×P2) +
`plan/PLAN-UX-POLISH-2026-07-02.md` (story-ready uitwerking: UXS-1…UXS-26 met
exacte bestanden/regels, code-aanpak en acceptatiecriteria — gebruik dát als
implementatiebron). Dit epic mapt sprint 1 (P0) op 53.1–53.4; sprint 2/3 = 53.5.

---

## 53.1 — Polish-sprint S-items (top-10 #1–#7)
- status: ready
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
- status: ready
- team: FEAT
- blockedBy: —

**Wat:** UX1: banner-thumbnails tonen placeholder-lagen ("Type to enter
text"-soep) op Home/gallery — verifieer eerst tegen de E37.18-sweep+migratie
(gemerged vandaag; herbake mogelijk nog niet getriggerd) en dek de resterende
paden + forceer herbake. UX2: canvas overflowt het venster zonder fit/zoom —
fit-to-window bij open + zoom-chip (hergebruik E27.10-recept).
**DoD:** verse checkout, 1100×760-venster: banners-gallery toont schone thumbs
en de Studio past in het venster; tests groen; Result-regel.

## 53.3 — DSThumbnailCard: AX + hover als één DS-story (UX28 + UX26, P0)
- status: in_progress
- owner: DS (2026-07-12, hervat op branch v2/e53-3-kaart-ax)
- team: DS
- blockedBy: —

**Wat:** portret-/bannerkaarten exposen geen AX-elementen (VoiceOver kan de kern
van de app niet bedienen — live geverifieerd). LET OP (correctie uit de
uitwerking): DSThumbnailCard heeft al scrim + dsHoverScale; het contrast-/AX-werk
zit in de gallery-kaart (PortraitsGalleryView.swift:244-253) — volg UXS-7 in het
PLAN-document, incl. DSIconButton-verplicht-label.
**DoD:** kaarten zijn met VoiceOver/AX-inspector bereikbaar en activeerbaar
(open/selecteer/contextmenu); tests groen; Result-regel.

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
- status: ready
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
