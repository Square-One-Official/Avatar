# E25 — Color picker (DSColorPicker)

Team: **DS** (AvatarUI) + **FEAT** (Avatar2 integratie). Autonome shift 2026-06-14.
Bron: referentie-screenshot (functioneel voorbeeld, niet 1-op-1 qua stijl) — bouwen in de
dark/lime-huisstijl met DS-componenten/tokens, zonder Figma. Figma-afwijkingen onder "Figma-TODO:".

Werkwijze per story: claim → Plan → bouwen → DoD (beide targets groen) → MERGE → Result
(done = ná merge). UI = visuele smoke + screenshot.

## 25.1 — DSColorPicker-component (AvatarUI)
- status: ready
- **Plan:** een herbruikbare `DSColorPicker` in AvatarUI met:
  - **HSV-veld** (saturation × value vlak) met een draggable, ZICHTBARE thumb (les uit 24.11: thumbs
    moeten duidelijk zichtbaar zijn);
  - **Hue-slider** (regenboog) met zichtbare thumb;
  - **Alpha-slider** met dambord-achtergrond (transparantie zichtbaar) + zichtbare thumb;
  - **Eyedropper** (macOS `NSColorSampler`) om een schermkleur te pikken;
  - **Hex-veld** + **opacity-%**-veld (DSTextField);
  - **Format-dropdown** (Hex default; ruimte voor RGB/HSL later);
  - dark/lime-huisstijl, DS-tokens/spacing/radius.
  - **API:** `DSColorPicker(color: Binding<Color>)` (+ optioneel `supportsAlpha`); kleur live terug
    via de binding. Definitieve API in de Result.

## 25.2 — Background-menu: "+" → DSColorPicker
- status: ready (na 25.1)
- **Plan:** vervang de losse eyedropper-knop in de Color-rij door een **"+"-knop HELEMAAL LINKS** in
  de Color-rij die de DSColorPicker opent (popover/sheet). De gekozen/gesamplede kleur wordt de
  achtergrond (`backgroundColorHex`) én een persistente brand-kit-swatch (`BrandColorKit`, E07.1).

## 25.3 — (optioneel) DSColorPicker hergebruiken
- status: backlog — overal waar een kleur gekozen wordt de DSColorPicker inzetten (consistentie).
