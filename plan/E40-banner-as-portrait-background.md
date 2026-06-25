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
- status: ready
- owner: —
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
- status: backlog
- owner: —
- team: FEAT
- blockedBy: 40.1

Onthoud welke banner als achtergrond is gekozen (`backgroundBannerID`) en bied, wanneer die banner
later in de Studio wijzigt, een "Update background"-actie/toast. Niet-blokkerend; alleen als
Thierry de koppeling wil.
- DoD: beide targets bouwen, tests groen, Result-regel.
