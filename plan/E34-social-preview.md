# E34 — Social Preview & Banner

Team: **FEAT** (+ AI voor de AvatarKit-engines, INFRA voor Portrait2/Shell + Phase-2 backend)

Een preview-modus in de editor die de avatar als profielfoto-in-context toont op LinkedIn,
X en Instagram, plus een banner achter de profielfoto die de avatar-achtergrond matcht,
een eigen kleur/afbeelding krijgt, of (Phase 2) AI-gegenereerd wordt. Achtergrond + besluiten:
zie het goedgekeurde plan (`~/.claude/plans/since-we-make-aaavatars-mutable-bonbon.md`).

Besluiten (Thierry, 2026-06-25): banner = preview **én** download-cover; AI gefaseerd ná de
MVP; trigger = Preview-knop in de topbar náást Share; chrome = code-getekend skeleton-wireframe
(avatar het enige scherpe/kleur-element).

## MVP — preview + match/choose banner (lokaal, geen credits)

## 34.1 — BannerCompositor + DominantColor (AvatarKit)
- status: done
- owner: AI (2026-06-25)
- DoD: beide targets bouwen, tests groen

**Result:** `BannerCompositor` (AvatarKit/Engines) — `composite(fill:size:)` rendert een
wijde, ondoorzichtige cover (kleur óf afbeelding aspect-fill) op volle doelmaat in
linear-sRGB; bewust apart van het vierkant-gekoppelde `BackgroundCompositor`. `DominantColor`
— `average`/`edge` via CIAreaAverage (rand-frame voor "de achtergrondkleur" van een
subject-portret). 3 unit-tests (wijde kleur-fill opaak, image aspect-fill, edge-sampling
negeert de kern) groen; volledige AvatarKit-suite groen.

## 34.2 — Portrait2 banner-velden + BannerBackground
- status: done
- owner: INFRA (2026-06-25)
- DoD: beide targets bouwen

**Result:** `Portrait2` kreeg `bannerColorHex` / `bannerImageData` (externalStorage) /
`bannerMatchesBackground` (default true) + computed `bannerBackground` value-object +
`setBannerBackground` (precies-één-modus-invariant, `touch()`), spiegelt `background`. Nieuwe
`BannerBackground`-enum (matchPortrait/color/image). Lichtgewicht migratie via de defaults.

## 34.3 — SocialPlatform + BannerResolver
- status: done
- owner: FEAT (2026-06-25)
- blockedBy: 34.1, 34.2

**Result:** `Avatar2/Features/SocialPreview/SocialPlatform.swift` (canonieke covermaten —
LinkedIn 1584×396, X 1500×500, IG geen cover — + profielcirkel-geometrie + `PreviewTab`
LinkedIn/X/Instagram/All) en `BannerResolver.swift` (mapt portret + `BannerBackground` →
`BannerCompositor.Fill`; match-modus leidt af uit `Portrait2.background`, met
`DominantColor.edge` van de originele foto als fallback voor transparant/origineel).

## 34.4 — PlatformChrome skeleton-wireframe
- status: done
- owner: FEAT (2026-06-25)
- blockedBy: 34.3

**Result:** `PlatformChrome.swift` — code-getekend, minimalistisch wireframe per platform uit
DS-tokens, geparametriseerd op `SocialPlatform`-geometrie. LinkedIn (4:1 cover, avatar
linksonder, headline + feed-card), X (3:1, avatar half onder de band, Follow-pill,
tweet-rijen), Instagram (geen cover, avatar + stats + bio + 3×3 grid). De avatar is het enige
scherpe/kleur-element; ruisvrij.

## 34.5 — Topbar Preview-knop + SocialPreviewView + Shell-wiring
- status: done
- owner: FEAT+DS (2026-06-25)
- blockedBy: 34.4

**Result:** `ShellModel.isShowingSocialPreview`/`canPreview`/`showSocialPreview()`;
`ShellTopBar` Preview-knop (oog-glyph) náást Share; `ShellView` rendert `SocialPreviewView` als
crossfade-overlay over de editor. `SocialPreviewView` — segmented-switcher (LinkedIn default ·
X · Instagram · All), ✕-sluitknop, live mockup (skeleton chrome → banner-laag → ronde
profielfoto via de bestaande export-pijplijn), rechts de banner-bediening. DEBUG smoke-haak
`--show-social-preview`.

## 34.6 — BannerPanel (match/kleur/gradient/upload)
- status: done
- owner: FEAT+DS (2026-06-25)
- blockedBy: 34.2

**Result:** `BannerPanel.swift` — slanke broer van `BackgroundPanel`: "Match avatar"-swatch
(default), Image-rij (upload + gradient-presets), Color-rij (presets + brand + DSColorPicker).
Schrijft `BannerBackground` via `onApply`, undo'baar (ReversibleChange) in de preview.
**Superseded (E34-feedback): vervangen door `BannerChooser` (E35.4) — de banner-keuze is nu
een aparte Banners-bibliotheek; `BannerPanel.swift` is verwijderd.**

## 34.7 — Banner-export (makeBannerPNG + per-platform Save)
- status: done
- owner: FEAT (2026-06-25)
- blockedBy: 34.1, 34.3, 34.5

**Result:** `PortraitExporter.makeBannerPNG(for:platform:watermark:)` via
`BannerResolver`+`BannerCompositor` op exacte covermaat; wijd hoek-watermerk voor free-tier.
`SocialPreviewView` exporteert per-platform: "Save profile picture" (ronde pic) + "Save
LinkedIn/X banner" (covers; IG heeft geen cover). NSSavePanel met platform-bestandsnamen.

---

## Follow-up — AI-generatie (backlog)

## 34.8 — Banner-generatie-bakeoff
- status: backlog
- blockedBy: 34.7

Kan nano-banana/flux-2/seedream een schone, persoonsvrije WIJDE achtergrond maken uit (a) een
portret-referentie en (b) alleen tekst? (spiegelt E09.1). Output: gekozen default + geverifieerde
wijd-aspect-afhandeling.

## 34.9 — Backend /v1/generate-banner
- status: backlog
- blockedBy: 34.8

`/v1/generate-banner.ts` + `MODEL_REGISTRY.banner` (4 credits) + `generateBanner`/`bannerInputFor`
in replicate.ts + `vercel.json` + `BackendClient.generateBanner`. Spiegelt de stylize-pijplijn
(auth/rate-limit/credit-gate); `sharp`-resize naar exacte covermaat.

## 34.10 — AI-sectie in BannerPanel
- status: backlog
- blockedBy: 34.9, 34.6

"Same style as photo" + "Describe a banner…" gewired op `generateBanner` met
allowCloudFeature/working-toast/credits/undo. Resultaat → `bannerBackground = .image(widePNG)`.
