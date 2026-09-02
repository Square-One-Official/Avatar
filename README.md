# Aaavatar

Native macOS-app die portretfoto's consistent verwerkt: achtergrond
verwijderen, automatisch uitlijnen op het gezicht, verbeteren, stijlen en met
één klik exporteren naar LinkedIn / Slack / e-mail / banners.

Deze repo bevat **twee apps**. **Aaavatar 2** (`Avatar2/`) is het actieve
project; **Aaavatar 1** (`Avatar/`) is sinds 2026-06-15 bevroren en moet
alleen blijven bouwen. Werk je met een agent: lees eerst
[`CLAUDE.md`](CLAUDE.md) en [`plan/BOARD.md`](plan/BOARD.md).

## Mentaal model

| Map | Wat | Eigenaar (zie CLAUDE.md) |
|---|---|---|
| `Avatar2/` | De 2.0-app. Compositie-root `Avatar2App.swift`; alles per feature in `Features/<naam>/` | INFRA (root) · FEAT (features) |
| `AvatarKit/` | Swift-package met services en engines: backend-client, auth (e-mail + OTP), cutout/imaging-engines, TLS-pinning | INFRA · AI (`Engines/`) |
| `AvatarUI/` | Swift-package met het design system: tokens (`DSColor`, `DSSpacing`, `DSMotion`, …) en DS-componenten, 1-op-1 uit Figma | DS |
| `backend/` | `avatars-api` op Vercel + Supabase: credits, Stripe, effects, appcast-feeds | INFRA |
| `admin/` | `avatar-admin`, Payload-CMS voor effects/berichten | INFRA |
| `plan/` | Bord, epics, beslissingen, go/no-go — de werkwijze en de bron van waarheid voor wat er gebouwd wordt | — |
| `docs/` | Engineering-, security- en legal-documentatie; o.a. het release-runbook | — |
| `scripts/` | DoD-gate, guards, release, model-conversie (zie `scripts/README.md`) | — |
| `Avatar/` | Aaavatar 1 — bevroren, niet aanraken buiten SHARED-stories | — |

### `Avatar2/Features/`

| Map | Inhoud |
|---|---|
| `Shell/` | Venster-shell: `ShellView`/`ShellModel`, home, left-nav, floating overlays, gedeelde presentatiestate |
| `Sidebar/` | SwiftData-modellen `Portrait2`, `Folder2` en het drag-item |
| `Portraits/` | Bibliotheek: mappen, breadcrumb, import-support |
| `Board/` | Grid-weergave met multi-select en batch-acties |
| `Editor/` | Canvas, transform/adjust/enhance-panelen, achtergrond, effects, undo-facades |
| `Background/` | Achtergrond genereren (Image Playground / cloud) |
| `Banners/` | Banner Studio (achter `AppFeatureFlags.bannersEnabled`, default uit) |
| `SocialPreview/` | Preview per platform + banner-export |
| `Share/` | Export- en rename-sheets |
| `Onboarding/` | Splash, privacy, modeldownload, e-mail + OTP |
| `Paywall/` | `EntitlementModel` (Pro, credits, checkout), paywall en toasts |
| `Settings/` | Preferences, AI-modellen/privacy-tiers, account, About + Sparkle-`UpdateManager` |
| `Shared/` | Thumbnails, links, kleine gedeelde helpers |

## Vereisten

- macOS 14 (Sonoma) of nieuwer
- Xcode 16 of nieuwer
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — het `.xcodeproj` wordt uit `project.yml` gegenereerd

## Bouwen & testen

```bash
xcodegen generate          # eerste keer of na nieuwe bestanden
open Avatar.xcodeproj      # scheme "Avatar2" (⌘R)
```

De Definition-of-Done-gate bouwt beide targets en draait alle suites:

```bash
scripts/build-v2.sh
```

Losse onderdelen:

```bash
xcodebuild -project Avatar.xcodeproj -scheme Avatar2 -configuration Debug build
xcodebuild -project Avatar.xcodeproj -scheme Avatar2 -configuration Debug test   # Avatar2Tests, gehost in de app
swift test --package-path AvatarKit --parallel
swift test --package-path AvatarUI --parallel
```

Twee guards draaien mee in de gate: `scripts/check-motion.sh` (alle animatie
via `DSMotion`, reduce-motion-bewust) en `scripts/check-icon-sizes.sh`
(icoongroottes via `DSIconSize`).

## Releasen

Zie [`docs/eng/RELEASE-2.0.md`](docs/eng/RELEASE-2.0.md): artefacten,
pipeline, waarom het kanaal zo in elkaar zit (eigen appcast, verplichte
prerelease), eenmalige setup, stappen per release, rollback en sleutels.
Script: `scripts/release-v2.sh <versie> <build>`. Status van de eerste
beta: [`plan/GO-NO-GO-2.0.md`](plan/GO-NO-GO-2.0.md).

## Verder lezen

- [`CLAUDE.md`](CLAUDE.md) — werkafspraken, ownership, Figma-bron
- [`plan/BOARD.md`](plan/BOARD.md) — het bord: epics, status, beslissingen
- [`plan/DECISIONS-PENDING.md`](plan/DECISIONS-PENDING.md) — open besluiten
- [`plan/ASSETS.md`](plan/ASSETS.md) — placeholder-register
- [`docs/security/`](docs/security/) — beleid, deploy-checklist, incident-response

---

# Aaavatar 1 (bevroren)

Onderstaande beschrijft de v1-app in `Avatar/`. Sinds 2026-06-15 gaat al het
nieuwe werk naar Aaavatar 2; v1 moet alleen blijven bouwen (de DoD-gate bouwt
'm mee) en het v1→v2-importpad blijft ondersteund.

Native macOS app voor HR die portretfoto's van medewerkers consistent verwerkt: AI achtergrond-verwijdering, automatische uitlijning op het gezicht, vaste achtergrond, en één-klik export naar LinkedIn / Slack / Email / generieke formaten.

Vervangt de Figma-workflow.

## Vereisten (v1)

- macOS 14 (Sonoma) of nieuwer — vereist voor Apple's `VNGenerateForegroundInstanceMaskRequest` (subject lift)
- Xcode 15 of nieuwer
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — alleen nodig om `.xcodeproj` te (her)genereren

## Bouwen & draaien (v1)

```bash
# Eerste keer (of na het toevoegen van bestanden):
xcodegen generate

# Open in Xcode en draai (⌘R):
open Avatar.xcodeproj
```

Of vanaf de command line:

```bash
xcodebuild -project Avatar.xcodeproj -scheme Avatar \
  -configuration Debug -destination 'platform=macOS' build \
  CODE_SIGNING_ALLOWED=NO
```

De `.app` komt in `~/Library/Developer/Xcode/DerivedData/Avatar-*/Build/Products/Debug/Avatar.app`.

## Hoe het werkt (v1)

1. **Importeer** een portretfoto (sleep op het venster, of `+` knop)
2. App roept `Vision.VNGenerateForegroundInstanceMaskRequest` aan → vrijstaande cutout
3. App roept `Vision.VNDetectFaceRectanglesRequest` aan → gezicht-bounding-box
4. `AutoAligner` plaatst de cutout zodat het gezicht 38% van de canvas-hoogte beslaat,
   gecentreerd op (50%, 42%). Hierdoor staan **alle portretten visueel identiek**
   ongeacht de oorspronkelijke compositie.
5. Lila kan handmatig nog slepen / schalen / van achtergrond wisselen
6. **Exporteer** met een of meer presets in één klik → PNG's in haar gekozen map

## Bestandsstructuur (v1)

```
Avatar/
├── AvatarApp.swift        App entry, ModelContainer
├── Models/                        SwiftData @Model classes
│   ├── Portrait.swift
│   ├── BackgroundPreset.swift
│   └── ExportPreset.swift
├── Services/
│   ├── AppState.swift             Observable shared state + image cache
│   ├── ImageProcessor.swift       Subject lift + face detection (Vision)
│   ├── AutoAligner.swift          Face → canonical canvas transform (pure)
│   ├── Compositor.swift           Background + cutout + circle mask render
│   ├── ExportService.swift        PNG writer
│   ├── SeedData.swift             Built-in presets first-run
│   └── ImportFlow.swift           File → Portrait pipeline
└── Views/
    ├── MainWindow.swift           NavigationSplitView wrapper
    ├── LibraryView.swift          Sidebar + search
    ├── ImportDropZone.swift       Empty-state drop target
    ├── EditorView.swift           Live canvas, drag/scale, controls
    ├── ExportSheet.swift          Multi-preset selector + folder picker
    └── SettingsView.swift         Backgrounds & export-preset management
```

## Built-in export presets (v1)

| Naam        | Afmetingen | Vorm    |
|-------------|-----------|---------|
| LinkedIn    | 400×400   | Cirkel  |
| Slack       | 512×512   | Vierkant|
| Email       | 256×256   | Cirkel  |
| Generiek L  | 1024×1024 | Vierkant|
| Generiek M  | 512×512   | Vierkant|
| Generiek S  | 256×256   | Vierkant|

Lila kan extra presets toevoegen via **Avatar → Settings… → Export presets**.

## Auto-alignment afstemmen (v1)

De drie magische getallen staan in [`Avatar/Services/AutoAligner.swift`](Avatar/Services/AutoAligner.swift):

```swift
static let targetFaceHeightRatio: CGFloat = 0.38
static let targetFaceCenterY: CGFloat = 0.42
static let targetFaceCenterX: CGFloat = 0.50
```

Pas deze aan om de huisstijl te matchen (kleinere koppen, meer ruimte boven, etc.).

## Bekend / nog niet in v1

- Geen batch-import van meerdere foto's tegelijk
- Geen undo/redo voor canvas-aanpassingen (auto-save bij elke wijziging)

## Distributie (v1)

Twee kanalen, beide vanuit dezelfde codebase:

- **DMG / website (`Avatar`-target)** — Sparkle auto-update via `appcast.xml`. Stripe-paywall voor Pro Magic Cutout.
- **Mac App Store (`Avatar-MAS`-target)** — `APP_STORE` compile-flag schakelt Sparkle uit en zet IAP/StoreKit aan. Update via App Store. Aparte entitlements ([Avatar-MAS.entitlements](Avatar/Avatar-MAS.entitlements)).

Schakelt automatisch tussen builds via Xcode-scheme of `xcodebuild -scheme {Avatar|Avatar-MAS} -configuration Release`.

### Eenmalige setup

```bash
# 1. App-specific password genereren op appleid.apple.com
#    → Sign-In and Security → App-specific passwords → +
# 2. Opslaan in Keychain als notarytool-profile (voor DMG-notarization):
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id thierryemmery@gmail.com \
  --team-id 5J92MMGKTX \
  --password <app-specific-password>
```

Voor App Store-upload heb je een Apple ID + app-specific password nodig die als argumenten aan `xcrun altool --upload-package` worden meegegeven, of een API-key via `xcrun notarytool` (zelfde profile werkt).

### DMG-release publiceren

Eenmalig: `brew install create-dmg` (nodig voor de gestileerde installer-window met app-icoon, Applications-shortcut en drag-and-drop pijl).

```bash
./scripts/release.sh 1.1 2   # MARKETING_VERSION=1.1, build=2
```

Dit script archiveert de `Avatar`-target, bouwt een gestileerde DMG, notariseert via Apple, staplet, ondertekent met Sparkle EdDSA, update `appcast.xml`, en publiceert naar GitHub Releases.

De achtergrond van het DMG-venster wordt gegenereerd door `scripts/dmg-assets/build-background.py` (Pillow). Pas de constanten boven in dat script aan om de boog, kleuren of caption te tweaken; commit daarna de gegenereerde `background.tiff`.

### Mac App Store-build uploaden

```bash
xcodebuild -project Avatar.xcodeproj -scheme Avatar-MAS -configuration Release \
  -archivePath build/Avatar-MAS.xcarchive archive

xcodebuild -exportArchive \
  -archivePath build/Avatar-MAS.xcarchive \
  -exportPath build/mas-export \
  -exportOptionsPlist scripts/ExportOptions-MAS.plist
```

Het laatste commando uploadt direct naar App Store Connect (via `destination: upload` in [ExportOptions-MAS.plist](scripts/ExportOptions-MAS.plist)). Daarna kies je in App Store Connect de geüploade build voor de juiste versie en submit je voor review.
