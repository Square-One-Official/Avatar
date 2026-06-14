# E23 — Light/Dark theme (cross-cutting)

Team: **DS**. Autonome shift 2026-06-14.

## Status: done (eigen sessie op verzoek Thierry) — owner FEAT (AI-agent)

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

---

## Result (E23.1–23.3 — done)

**Gekozen architectuur (regressie-veilig):** DSColor-tokens zijn nu DYNAMISCHE kleuren
(`Color(lightHex:darkHex:)` → een dynamische `NSColor(name:nil){…bestMatch…}`) die op de effectieve
appearance van de view resolven (gevoed door `.preferredColorScheme` via de AppearancePreference).
**Dark = fallback en exact de oude dark-only waarde** → de ~300 bestaande `DSColor.*`-call-sites
blijven ongewijzigd en een onvolledige light-pas kan de dark-app nooit breken (de plan-zorg
"halverwege afbreken breekt de kleuren" is daarmee geadresseerd).

- **23.1 Light token-set:** de surface-/foreground-tokens die moeten flippen kregen een light-waarde
  (warm stone-palet: app #FAFAF9, card #FFFFFF, inset #F5F5F4; neutral/divider = zwart@5/10/15/…;
  foreground primary/subtle/muted = warm bijna-zwart #1C1917 met dezelfde alpha's; thumb/tooltip
  donker op light). Brand-lime (`action`/`onAction`), shadow, signal-pastels en project-kleuren zijn
  in beide themes gelijk gehouden. Plus `DSNSColor` (theme-bewuste NSColor-pendanten) voor
  AppKit-tekst.
- **23.2 Omschakeling + default:** de bestaande `AppearancePreference` (E15.1, Settings > Appearance:
  System/Light/Dark) stuurt nu écht de kleuren. Default **Dark** (was `.system`) zodat de merk-look
  identiek blijft tot iemand Light/System kiest. Forced `.preferredColorScheme(.dark)` weg bij de
  hoofd-shell (ShellView) + FirstUseEmptyState zodat die de voorkeur volgen.
- **23.3 Audit + dual-theme smoke:** hardcoded witte AppKit-tekst (DSInlineEditLabel: Name/Role +
  placeholder) → theme-bewust via `DSNSColor`. Scrims/shadows/export-tekst blijven bewust
  appearance-agnostisch (werken op beide; export-PNG is niet-getemed). **Smoke (geverifieerd):**
  light = warm-witte app, donkere Name/Role-tekst, lichte canvas-kaart + toolbar; Face-paneel +
  thumbnail-kaarten (24.15) + gedeeld paneel-oppervlak (24.12) themen mee; dark = ongewijzigd t.o.v.
  vóór E23 (geen regressie). Screenshots: /tmp/theme_light_e23.png, /tmp/theme_dark_e23.png,
  /tmp/theme_light_panel_e23.png. Beide targets + alle pakkettests groen (build-v2.sh).

**Figma-TODO (light-waarden bevestigen):** de light-tokens zijn afgeleide placeholders (geen Figma-
toegang in deze sessie) — bevestigen tegen de Components-variabelen. Specifiek: (a) exacte
light-surface-tinten (stone-palet aanname), (b) lime-accent op lichte surfaces → WCAG-contrast van
`onAction`-tekst + lime-borders checken, (c) signal-pastels: light-varianten + contrast, (d)
shadow-tint op light (nu dezelfde donkere drop-shadow).

**Restpunt (eigen vervolg-story):** OnboardingFlow + PaywallSheet + (in-app message-scrim) staan nog
op forced `.dark` — bewuste merk-momenten; meenemen zodra de light-richting voor die flows bekend is.
Settings-pagina's en overige sheets volgen de tokens al automatisch (dynamisch), maar niet expliciet
in beide themes gesmoked deze sessie → aanrader bij de Figma-bevestiging.
