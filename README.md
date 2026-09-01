# Avatar

Native macOS app voor HR die portretfoto's van medewerkers consistent verwerkt: AI achtergrond-verwijdering, automatische uitlijning op het gezicht, vaste achtergrond, en één-klik export naar LinkedIn / Slack / Email / generieke formaten.

Vervangt de Figma-workflow.

## Cursor / Git-workflow

Uitleg waarom Cloud Agents altijd een PR maken, hoe dat samenhangt met Xcode, en hoe je van idee naar `v2-main` werkt zonder chaos:

- [`docs/cursor-git-workflow-guide.md`](docs/cursor-git-workflow-guide.md) (leesbaar op GitHub)
- [`docs/cursor-git-workflow-guide.html`](docs/cursor-git-workflow-guide.html) (visueel, open lokaal in de browser)

> Staat op `v2-main`. Pad: `docs/` in de **repo-root** — niet `Avatar2/docs/`. Zit je in `Avatar2/`? Open dan `../docs/cursor-git-workflow-guide.html`.

## Vereisten

- macOS 14 (Sonoma) of nieuwer — vereist voor Apple's `VNGenerateForegroundInstanceMaskRequest` (subject lift)
- Xcode 15 of nieuwer
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — alleen nodig om `.xcodeproj` te (her)genereren

## Bouwen & draaien

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

## Hoe het werkt

1. **Importeer** een portretfoto (sleep op het venster, of `+` knop)
2. App roept `Vision.VNGenerateForegroundInstanceMaskRequest` aan → vrijstaande cutout
3. App roept `Vision.VNDetectFaceRectanglesRequest` aan → gezicht-bounding-box
4. `AutoAligner` plaatst de cutout zodat het gezicht 38% van de canvas-hoogte beslaat,
   gecentreerd op (50%, 42%). Hierdoor staan **alle portretten visueel identiek**
   ongeacht de oorspronkelijke compositie.
5. Lila kan handmatig nog slepen / schalen / van achtergrond wisselen
6. **Exporteer** met een of meer presets in één klik → PNG's in haar gekozen map

## Bestandsstructuur

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

## Built-in export presets

| Naam        | Afmetingen | Vorm    |
|-------------|-----------|---------|
| LinkedIn    | 400×400   | Cirkel  |
| Slack       | 512×512   | Vierkant|
| Email       | 256×256   | Cirkel  |
| Generiek L  | 1024×1024 | Vierkant|
| Generiek M  | 512×512   | Vierkant|
| Generiek S  | 256×256   | Vierkant|

Lila kan extra presets toevoegen via **Avatar → Settings… → Export presets**.

## Auto-alignment afstemmen

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

## Distributie

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
