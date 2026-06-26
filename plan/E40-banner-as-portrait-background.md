# E40 — Banner als portret-achtergrond

Team: **FEAT**

Voortgekomen uit feedback (Thierry, 2026-06-26): "die banner ook als achtergrond kunnen gebruiken
voor portret". Sluit de cirkel: een gemaakte banner is herbruikbaar als achtergrondbeeld van een
portret.

Bestaande haak: `Portrait2.background` is een precies-één-modus value-object
(`transparent`/`original`/`color`/`image(Data)`) met atomische setter; de `BackgroundPanel`
toont upload + CMS-backgrounds + presets. Een banner is een wijde PNG → past in `.image(Data)`.

---

## 40.1 — "Use a banner" als achtergrond-bron in BackgroundPanel
- status: done
- owner: FEAT (2026-06-26)

**Result:** [BackgroundPanel](Avatar2/Features/Editor/BackgroundPanel.swift) kreeg een **"Banners"**-sectie (alleen zichtbaar als er ≥1 banner met preview is): wijde tegels van `BannerDoc.previewImageData` → `apply(.image(data))` (undo'baar via het bestaande apply-pad; geselecteerde banner krijgt een ring). Sluit de cirkel — een in de Studio gemaakte banner is herbruikbaar als portret-achtergrond. DoD groen.
- team: FEAT
- blockedBy: 37.1

- Voeg in [BackgroundPanel](Avatar2/Features/Editor/BackgroundPanel.swift) een **"Banners"**-bron
  toe: een rij/raster van opgeslagen banners (`Banner2` + nieuwe `BannerDoc`-previews) waaruit je
  kiest → `setBackground(.image(bannerPNG))` (undo'baar). Banner is wijd; voor de
  portret-achtergrond aspect-fill/crop net als andere image-backgrounds.
- Toon dit alleen als er ≥1 banner is; anders een subtiele "Make a banner"-link (→ Studio).
- **Geen Figma-ref** — DS-tokens; patroon = bestaande image-rij in `BackgroundPanel`.
- DoD: beide targets bouwen, tests groen, Result-regel.

## 40.2 — (Optioneel) live-koppeling banner→achtergrond
- status: done
- owner: FEAT (2026-06-26)
- team: FEAT
- blockedBy: 40.1
- Result: `Portrait2` kreeg `backgroundBannerID: String?` (lichtgewicht migratie, default nil) =
  de encoded `PersistentIdentifier` van de bron-`BannerDoc`; `setBackground` wist 'm altijd en
  alléén de banner-bron zet 'm terug, zodat enkel een uit-een-banner overgenomen achtergrond
  gekoppeld blijft. `BackgroundPanel.bannersRow` (E40.1) gebruikt nu die sleutel: een gekoppeld
  portret toont de selectie-ring óók nadat de banner is gewijzigd, en wanneer de opgeslagen bytes
  achterlopen op `BannerDoc.previewImageData` verschijnt een subtiel **"Update"**-vaantje
  (rechtsboven) — klik = `applyBanner(doc)` herpast de verse preview + herstelt de koppeling. De
  koppeling wordt alleen in de enkel-portret-editor gelegd (niet in de board-batch). De "toast"
  uit de story is bewust ingeperkt tot deze inline in-panel-actie (geen globale toast-plumbing
  nodig; blijft binnen het paneel dat 40.1 bouwde). DoD groen: Avatar2 bouwt, build-v2.sh "alles
  groen".

Onthoud welke banner als achtergrond is gekozen (`backgroundBannerID`) en bied, wanneer die banner
later in de Studio wijzigt, een "Update background"-actie/toast. Niet-blokkerend; alleen als
Thierry de koppeling wil.
- DoD: beide targets bouwen, tests groen, Result-regel.
