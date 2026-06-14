# E23 — Light/Dark theme (cross-cutting)

Team: **DS**. Autonome shift 2026-06-14.

## Status: GEPARKEERD (bewust, met plan) — niet gestart in deze marathon

**Waarom geparkeerd:** E23 is een grote cross-cutting refactor. `DSColor` is nu een set
**dark-only constanten** (`Color(hex:)`), direct gebruikt door tientallen componenten. Light-mode
betekent élke kleur theme-bewust maken (environment-driven) — dat raakt de hele DS-laag en alle
call-sites. Halverwege afbreken zou de kleuren van de hele app breken. Beter als één gefocuste
story met smokes in BEIDE themes, los van deze marathon (regressie-risico te hoog om af te raffelen
aan het eind van een lange sessie).

## Plan (voor de dedicated sessie)
- **23.1** Light token-set: per `DSColor`-token een light-waarde uit de Figma-variabelen
  (let op: lime-accent op lichte surfaces → WCAG-contrast checken; on-action/foreground-paren).
- **23.2** `DSTheme`-environment + omschakeling: maak `DSColor` theme-bewust (bv. een
  `@Environment(\.dsTheme)` of een resolver), schakelaar in Settings > Preferences > Appearance
  (Dark default / Light / System). Sluit aan op de bestaande `AppearancePreference` (E15.1).
- **23.3** Audit hardcoded kleuren → via tokens; smoke in BEIDE themes (alle hoofdschermen +
  panelen + popovers + toasts).

**Afhankelijkheid:** raakt alles wat in deze marathon is bijgebouwd (canvas-toolbar, panelen,
export/rename-sheets, tooltips, sign-in) — dus ná de IA-revisie (E24) doen is juist (minder herwerk).
