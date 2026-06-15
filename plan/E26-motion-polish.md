# E26 — Motion & animatie-polish (cross-cutting)

Team: **DS** (token + AvatarUI-componenten) + **FEAT** (Avatar2-features).
Aangemaakt 2026-06-15 op verzoek Thierry (design-engineering audit).

## Status: in_progress (26.1 done)

Cross-cutting refactor in de geest van [E23 Theming](E23-theming.md): één
gedeelde token-laag + audit van alle call-sites. Net als E23 raakt dit de hele
DS-laag, dus regressie-veilig opzetten (dark = exact de huidige waarden;
"Verminder beweging" mag nooit een scherm breken). Mag pas `done` als **beide
targets bouwen** (`Avatar` én `Avatar2`) en de reduced-motion-smoke in **beide
themes** klopt.

## Audit-weging

Aaavatar is een dagelijks productiviteitstool met speelse merk-copy. Lens:
**Emil Kowalski (primair)** terughoudendheid + snelheid + custom-easing-punch +
"moet dit überhaupt animeren?" (frequentie) → **Jakub Krehel (secundair)**
productie-polish: animeer loading/icon-swaps, exits subtieler dan enters, geen
snappende state-changes → **Jhey (selectief)** delight alléén op zeldzame
eerste-indruk-momenten (onboarding-splash, isolating-reveal). UI-animaties
< ~300ms; nooit animeren op hoogfrequente of toetsenbord-acties.

## Waarom dit op de lijst staat

De motion in v2 is al smaakvol en terughoudend, maar de audit legde drie
systemische gaten bloot:

1. **Geen gedeelde motion-tokens.** De `AvatarUI/Tokens`-laag heeft `DSColor`,
   `DSLayout`, `DSTypography`, `DSOpacity`, `DSRadius` — maar **geen `DSMotion`**.
   Duur/curve staan hardcoded verspreid over componenten en features, met drift:
   `0.1 / 0.12 / 0.14 / 0.15 / 0.18 / 0.2 / 0.25 / 0.3 / 0.35 / 0.4 / 0.45 / 0.8`
   coexisteren, en springs gebruiken `.spring(duration:)` met impliciete bounce.
2. **"Verminder beweging" wordt nergens gehonoreerd** — `accessibilityReduceMotion`
   komt in noch `AvatarUI` noch `Avatar2` voor. Toegankelijkheid is niet optioneel.
3. **Motion-gaps** — state-changes die zonder transitie klappen (canvas
   state-machine, settings-swap, paywall topup↔chooser, sign-in fase-wissel,
   DSToast, select-ring/spinner op thumbnails, achtergrond-swap in de editor).

Daarnaast gebruikt elke `.easeOut(duration:)` SwiftUI's ingebouwde curve, die
'punch' mist (Emil's eerste easing-punt). Eén custom curve in de token-laag lost
dat overal in één keer op.

## Bewuste scope-keuzes (LEES DIT)

- **Knop-/chip-feedback blijft opacity-gebaseerd.** `DSStateOpacityButtonStyle`
  (Default/Hover/Pressed/Disabled = `DSOpacity` 1/.75/.5/.25) is Figma-bron —
  **géén `scale(0.97)` toevoegen**. De polish hier is: de `.easeOut(0.1)` via een
  token + reduced-motion-bewust maken, niet het model omgooien.
- **Dark blijft identiek.** Tokens nemen de huidige waarden over; alléén de
  ease-out-curve verandert subtiel. Side-by-side smoken.
- **Ownership-grenzen (board-regel 4):** DS bezit `AvatarUI/`, FEAT bezit
  `Avatar2/Features/<naam>/`. Daarom is dit epic in DS- en FEAT-stories gesplitst.
- `Avatar/` (v1) is verboden terrein — dit epic raakt het niet.
- Regelnummers hieronder zijn indicatief (audit drift) — **verifieer met `grep`
  vóór je edit**.

---

## Stories

| ID | Story | Team | Status | Branch |
|----|-------|------|--------|--------|
| 26.1 | `DSMotion`-token + reduced-motion-helpers | DS | done | `v2/E26-26.1` |
| 26.2 | AvatarUI call-sites → tokens + reduced-motion | DS | backlog | `v2/E26-26.2` |
| 26.3 | DS-component motion-gaps dichten | DS | backlog | `v2/E26-26.3` |
| 26.4 | Avatar2-features call-sites → tokens + reduced-motion | FEAT | backlog | `v2/E26-26.4` |
| 26.5 | Feature motion-gaps dichten (high/medium) | FEAT | backlog | `v2/E26-26.5` |
| 26.6 | Verificatie & acceptatie (dual-theme + reduced-motion) | DS+FEAT | backlog | `v2/E26-26.6` |

Aanbevolen volgorde: 26.1 → 26.2 → 26.3 → 26.4 → 26.5 → 26.6. Alles na 26.1 is
los te shippen. 26.1 blokkeert al het andere.

---

### 26.1 — `DSMotion`-token + reduced-motion-helpers  · DS
- status: done
- owner: DS (AI-agent, motion-audit)

**Result:** `AvatarUI/Sources/AvatarUI/Tokens/DSMotion.swift` toegevoegd naast
`DSColor`/`DSLayout`/`DSTypography` (zelfde `public enum`-conventie). Bevat: de
custom ease-out-curve `timingCurve(0.23, 1, 0.32, 1, duration:)` (Emils 'punch'),
semantische duur-tokens `micro/fast/base/emphasis` (0.10/0.15/0.20/0.25) die de
verspreide 0.1–0.45-literals vervangen, twee bounce-0 springs
`springSmall`(0.30)/`springTransform`(0.40), de reduced-motion-bewuste
view-modifier `.dsMotion(_:value:)` (`@Environment(\.accessibilityReduceMotion)`)
voor declaratieve sites, en `DSMotion.animate(_:_:)` + `reduceMotionEnabled`
(`NSWorkspace…accessibilityDisplayShouldReduceMotion`) voor imperatieve
`withAnimation`-sites. Geen call-sites gemigreerd (dat is 26.2/26.4); geen
knop-model gewijzigd (opacity-scope intact, geen scale(0.97)).

**DoD/Verificatie:** `scripts/build-v2.sh` groen — beide targets (`Avatar` v1 +
`Avatar2`) bouwen, Avatar2-unit + AvatarKit + 27 AvatarUI-pakkettests groen.
`DSMotion`, `.dsMotion(_:value:)` en `DSMotion.animate(_:_:)` zijn `public` en
zichtbaar in Avatar2 (compileert mee). Reduced-motion-gedrag zelf wordt
end-to-end gesmoked zodra de eerste call-sites in 26.2 omgezet zijn.

**Doel:** één bron van waarheid voor duur + curve, mét ingebouwde
reduced-motion-ondersteuning. Plaats naast de bestaande tokens:
`AvatarUI/Sources/AvatarUI/Tokens/DSMotion.swift`.

```swift
import SwiftUI
import AppKit

/// Bewegings-tokens (duur + curve) voor de hele app — één bron van waarheid,
/// net als DSColor/DSLayout/DSTypography. Honoreert "Verminder beweging".
public enum DSMotion {
    /// Sterkere ease-out dan SwiftUI's ingebouwde (die mist 'punch').
    /// cubic-bezier(0.23, 1, 0.32, 1).
    public static func easeOut(_ duration: Double) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    // Semantische duur-tokens (vervangen de losse 0.1–0.45 literals).
    public static let micro    = easeOut(0.10) // hover/press-dim, tooltip, drag-handle
    public static let fast     = easeOut(0.15) // validatie, active-ring, grid-fade
    public static let base     = easeOut(0.20) // kleine toasts, toggles, banners
    public static let emphasis = easeOut(0.25) // stap-/sectiewissels (onboarding)

    // Springs — expliciete bounce (Jakub: bounce 0 = professioneel, geen overshoot).
    public static let springSmall     = Animation.spring(duration: 0.30, bounce: 0) // kleine moves, status-toast
    public static let springTransform = Animation.spring(duration: 0.40, bounce: 0) // canvas-transform, align-set, sidebar

    /// macOS "Verminder beweging"-vlag voor imperatieve withAnimation-sites.
    public static var reduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Reduced-motion-bewuste withAnimation. Gebruik op élke withAnimation-site.
    public static func animate(_ animation: Animation, _ body: () -> Void) {
        withAnimation(reduceMotionEnabled ? nil : animation, body)
    }
}

public extension View {
    /// Reduced-motion-bewuste vervanger voor `.animation(_:value:)`.
    /// Geeft nil door (beweging uit) als de gebruiker "Verminder beweging" aan heeft.
    func dsMotion<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(DSMotionModifier(animation: animation, value: value))
    }
}

private struct DSMotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
```

**Mapping bestaande waarden → token** (voor 26.2/26.4):

| Huidig | Token |
|---|---|
| `.easeOut(0.10)`, `.easeOut(0.12)` | `DSMotion.micro` |
| `.easeOut(0.14)`, `.easeOut(0.15)`, `.easeInOut(0.15)` | `DSMotion.fast` |
| `.easeOut(0.18)`, `.easeOut(0.2)` | `DSMotion.base` |
| `.easeInOut(0.25)` (onboarding-stap) | `DSMotion.emphasis` |
| `.spring(0.3)`, `.spring(0.35)` | `DSMotion.springSmall` |
| `.spring(0.4)`, `.spring(0.45)` | `DSMotion.springTransform` |
| `IsolatingTiming.backgroundFade` (0.8s reveal) | blijft eigen sequence-timing — niet tokeniseren |

**Acceptatie:** AvatarUI bouwt; `DSMotion`, `.dsMotion(_:value:)` en
`DSMotion.animate(_:_:)` zijn `public` en beschikbaar in Avatar2.

---

### 26.2 — AvatarUI call-sites → tokens + reduced-motion  · DS

**Doel:** elke animatie in `AvatarUI/Sources/AvatarUI/` loopt via een token én is
reduced-motion-bewust.

- `.animation(.easeOut(duration: X), value:)` → `.dsMotion(<token>, value:)`.
- `.animation(.spring(duration: X), value:)` → `.dsMotion(<springSmall/Transform>, value:)`.
- `withAnimation(...) { }` → `DSMotion.animate(<token>) { }`.

Bekende sites (verifiëren met grep): `DSButtonStyles.swift:22` (opacity-hover —
model behouden, alleen token), `DSToolButton.swift:58/90/94`,
`DSSidebarRow.swift:82`, `DSToggle.swift:64/65/66`, `DSOTPField.swift:46`,
`DSTextField.swift:76`, `DSEditPanel.swift:135/145`, `DSCanvasCard.swift:45`,
`DSHover.swift:31/43`, `DSIconButton.swift:81`, `DSInlineEditLabel.swift:145`,
`DSGhostButton.swift:72`.

**Acceptatie:** `grep -rn "easeOut(duration\|easeInOut(duration\|spring(duration\|withAnimation(\.\|\.spring(response" AvatarUI/Sources`
levert (vrijwel) niets meer op. Knop-opacity-model ongewijzigd.

---

### 26.3 — DS-component motion-gaps dichten  · DS

**Doel:** geen snappende state-changes in DS-componenten (Jakub: enter =
opacity + kleine offset/scale; exit subtieler; reduced-motion via 26.1-helpers).

1. **DSToast** — show/hide animeert nu niet. Voeg
   `.transition(.move(edge:).combined(with: .opacity))` + `.dsMotion(.springSmall, value:)`
   toe (DSToast wordt door features als overlay getoond — coördineer met 26.5).
2. **DSThumbnailCard** — select-ring + checkmark (`isSelected`) en de
   loading-spinner/dim-overlay (`isWorking`) klappen erin/eruit. Animeer ring +
   check (opacity + scale 0.9) en fade de spinner-overlay.
3. **DSInlineEditLabel** — `if isEditing { TextField } else { Text }` swap klapt
   (alleen de hover-bg fade'd). Animeer de swap (opacity/blur) of `.contentTransition`.
4. **DSProChip / DSFeatureIndicator** — conditionele indicator verschijnt/verdwijnt
   zonder transitie; voeg een opacity-fade toe.
5. **DSEditPanel** — container slide is OK; interieur-content verschijnt instant.
   Optioneel: lichte fade/stagger op de panel-inhoud.

**Acceptatie:** de vijf gevallen transitionen vloeiend; exits subtieler dan
enters; honoreren reduced-motion.

---

### 26.4 — Avatar2-features call-sites → tokens + reduced-motion  · FEAT

**Doel:** idem 26.2 maar voor `Avatar2/Features/` + `Avatar2/Avatar2App.swift`.

Bekende sites (verifiëren met grep): `Avatar2App.swift:76/105/107/108/172`,
`Shell/ShellView.swift:47/50/86/89/225/228/229`, `Sidebar/SidebarView.swift:280/309/357`,
`Editor/EditorCanvasView.swift:131/198/368/468`, `Editor/EditorView.swift:177`,
`Editor/CanvasActionToolbar.swift:77/111`, `Editor/AutoFramer.swift:232`,
`Settings/SignInSheet.swift:53/60`, `Paywall/PaywallSheet.swift:102` (+ `:168`
`.contentTransition(.numericText())` laten staan). `Shell/IsolatingCanvas.swift:35`
(0.8s reveal) houdt zijn eigen `IsolatingTiming`, maar wikkel hem wél in
`DSMotion.animate`-equivalent zodat reduced-motion ook hier geldt.

**Acceptatie:** grep-sweep over `Avatar2/` schoon; alle features reduced-motion-bewust.

---

### 26.5 — Feature motion-gaps dichten (high/medium)  · FEAT

**Doel:** geen klappende swaps op de meest-geziene vlakken. Reduced-motion via
26.1-helpers; exits subtieler dan enters.

**High:**
1. **ShellView.swift:248–289** — canvas state-machine (`.empty → .processing →
   .revealing → .result → .failed`). Elke tak rendert totaal andere content
   zonder transitie. Voeg een opacity-crossfade per tak toe (`.base`). ⚠️ Test op
   flikkering bij de zware editor/IsolatingCanvas; zo nodig animatie alleen op de
   lichtere takken (geen animatie op een vaak-geopende editor is Emil-correct).
2. **ShellView.swift:151–162** — settings ↔ canvas/editor swap klapt. Crossfade
   of move toevoegen.

**Medium:**
3. **PaywallSheet.swift:16–31** — `showsTopup` topup ↔ planChooser swap (incl.
   breedte-shift) klapt. Transitie + `.emphasis`.
4. **SignInSheet.swift:34–39** — email ↔ otp fase-swap klapt. Crossfade/slide.
5. **EditorView.swift:331–349** — hold-to-compare image-swap; `.transition(.opacity)`.
6. **EditorView.swift:189–203** — achtergrond image ↔ kleur swap klapt; cross-dissolve.
7. **EditorView.swift:396–455** — bottom-panel content-swap per tool; fade op de
   interieur-content (samen met DSEditPanel uit 26.3).
8. **SidebarView.swift:66–86** — lijst insert/delete leunt op default-SwiftUI;
   expliciete `.transition` per `DSSidebarRow`.
9. **SidebarView.swift:135–152** — context-menu-overlay verschijnt instant; fade.
10. **EditorCanvasView.swift:121–123** — selectie-handles klappen erin (fade'n
    alleen eruit tijdens drag); voeg fade-in op `isSelected` toe.

(Al OK — niet aankomen: `CanvasActionToolbar` dropdown `:111`, `OnboardingFlow`
stap-crossfade, `SignInSheet` auth-toast `:53/60`, alignment-guide `:468`.)

**Acceptatie:** de 10 gevallen transitionen vloeiend; geen snaps; reduced-motion OK.

---

### 26.6 — Verificatie & acceptatie  · DS+FEAT

1. **Build** — beide targets: `xcodebuild -scheme Avatar -destination 'platform=macOS' build`
   én `-scheme Avatar2`. Nul nieuwe warnings/errors. (Scheme's checken met
   `xcodebuild -list`.)
2. **Reduced-motion-gate** — Systeeminstellingen → Toegankelijkheid → Beeld →
   **Verminder beweging** aan; alle beweging/scale/spring wordt instant, state
   blijft leesbaar. Faalt nu overal → moet hierna overal slagen.
3. **Dual-theme-smoke** (sluit aan op E23) — hoofdschermen + panelen + popovers +
   toasts in **light én dark**: geen rare flikkering door de nieuwe curve/transities.
4. **Token-sweep** —
   `grep -rn "easeOut(duration\|easeInOut(duration\|spring(duration\|spring(response" AvatarUI/Sources Avatar2`
   (vrijwel) leeg.
5. **Geen regressies** in de kern-flow import → edit → export.
6. **Result:**-regel per story invullen (DoD).

---

## Risico's

| Risico | Kans | Mitigatie |
|---|---|---|
| Canvas-crossfade flikkert de zware editor/IsolatingCanvas | Midden | 26.5.1: animatie alleen op lichte takken; geen animatie op vaak-geopende editor |
| Custom ease-out wijzigt de Figma-feel van 0.1s-dims | Laag | Op 0.1s is curve-effect minimaal; side-by-side smoke; springs houden bounce 0 |
| Opacity-knopmodel per ongeluk vervangen door scale | Laag | Expliciete scope-keuze: alléén token + reduced-motion, model intact |
| `withAnimation` reduced-motion (AppKit-vlag) vs `.dsMotion` (SwiftUI-env) lopen uiteen | Laag | Beide lezen dezelfde OS-voorkeur; in views `.dsMotion`, alleen imperatief `DSMotion.animate` |
| Story raakt buiten team-grens (DS-component vanuit een feature) | Midden | Board-regel 4: voeg story toe bij juiste team i.p.v. zelf over de grens editen |

## Wanneer herzien

- Nieuwe views/componenten → motion meteen via `DSMotion`-tokens (geen inline literals).
- Als een toekomstige SwiftUI `accessibilityReduceMotion` ook imperatief leesbaar
  maakt → `DSMotion.animate` en `.dsMotion` op één pad samenvoegen.
