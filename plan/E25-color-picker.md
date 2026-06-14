# E25 — Color picker (DSColorPicker)

Team: **DS** (AvatarUI) + **FEAT** (Avatar2 integratie). Autonome shift 2026-06-14.
Bron: referentie-screenshot (functioneel voorbeeld, niet 1-op-1 qua stijl) — bouwen in de
dark/lime-huisstijl met DS-componenten/tokens, zonder Figma. Figma-afwijkingen onder "Figma-TODO:".

Werkwijze per story: claim → Plan → bouwen → DoD (beide targets groen) → MERGE → Result
(done = ná merge). UI = visuele smoke + screenshot.

## 25.1 — DSColorPicker-component (AvatarUI)
- status: done
- owner: DS (AI-agent, marathon 2)

**Result:** `DSColorPicker` (AvatarUI/Components/DSColorPicker.swift) — HSV-veld (saturation × value,
draggable), hue-slider (regenboog), alpha-slider (dambord + kleur-gradient), eyedropper
(`NSColorSampler`), hex-veld (DSTextField, two-way), opacity-%, en format-dropdown (Hex default;
RGB/HSL als placeholder). Alle thumbs zijn ZICHTBARE witte ringen met schaduw (les uit 24.11). HSV↔
Color via `NSColor.getHue…`. In de dark/lime-huisstijl op `dsPanelSurface`.
**API:**
```swift
DSColorPicker(color: $color)                    // met alpha-slider
DSColorPicker(color: $color, supportsAlpha: false)
```
De gekozen kleur komt live terug via de `color`-binding (HSV→Color in `push()`; hex/eyedropper→HSV).

**DoD/Verificatie:** beide targets + alle pakkettests groen (incl. AvatarUI-package-compile). Smoke
(`--show-colorpicker`, #if DEBUG): de picker toont HSV-veld + zichtbare thumb, hue/alpha-sliders,
eyedropper, Hex-dropdown, hex-veld (#45B5E5) + 100% (/tmp/c25_1_picker.png).
**Figma-TODO:** definitieve maatvoering/tints; RGB/HSL-formats activeren; precieze thumb-stijl tegen
de referentie-screenshot.
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
- status: done
- owner: FEAT (AI-agent, marathon 2)

**Result:** de losse eyedropper-knop in de Color-rij is vervangen door een **"+"-knop HELEMAAL
LINKS** die een `DSColorPicker` (zonder alpha) in een `.popover` opent. Terwijl de picker open is
werkt de achtergrond live mee (`onChange(pickerColor)` → `selectColor(hex)`); bij sluiten wordt de
kleur als persistente brand-swatch bewaard (`BrandColorKit.add`). De picker heeft zijn eigen
eyedropper (NSColorSampler), dus de losse knop is overbodig.

**DoD/Verificatie:** beide targets + tests groen. Screenshot: Background-dropdown met de "+" links in
de Color-rij (vóór de presets) (/tmp/c25_2_bg.png); DSColorPicker-render is in 25.1 bevestigd. De
"+"-klik → picker → bg/brand-wiring is via `onChange` gewired.
**Figma-TODO:** popover-positionering vanuit de toolbar-dropdown bevestigen; of de gekozen kleur
altijd als brand-swatch moet of alleen op expliciet opslaan.
- **Plan:** vervang de losse eyedropper-knop in de Color-rij door een **"+"-knop HELEMAAL LINKS** in
  de Color-rij die de DSColorPicker opent (popover/sheet). De gekozen/gesamplede kleur wordt de
  achtergrond (`backgroundColorHex`) én een persistente brand-kit-swatch (`BrandColorKit`, E07.1).

## 25.3 — (optioneel) DSColorPicker hergebruiken
- status: backlog — overal waar een kleur gekozen wordt de DSColorPicker inzetten (consistentie).
