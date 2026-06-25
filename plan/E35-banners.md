# E35 — Banners library

Team: **FEAT** (+ INFRA voor het Banner2-model/container)

Voortgekomen uit de E34-feedback (Thierry, 2026-06-25): de banner-keuze zat verstopt in de
preview en de "match avatar"-crop oogde matig. Besluit: een **aparte Banners-bibliotheek** —
herbruikbare, WIJDE banners (één beeld; upload of gradient-preset, later AI) — die je in de
social-preview kiest. Geen design-canvas.

## 35.1 — Banner2-model + container
- status: done
- owner: INFRA (2026-06-25)

**Result:** `Banner2` @Model (`name`, `createdAt`, `updatedAt`, externalStorage `imageData`,
`touch()`) in `Avatar2/Features/Banners/`; geregistreerd in de app-`modelContainer`
([Avatar2App.swift](Avatar2/Avatar2App.swift)) náást Portrait2/Folder2 (lichtgewicht migratie,
geen relaties).

## 35.2 — Banners-sectie + left-nav
- status: done
- owner: FEAT (2026-06-25)

**Result:** `ShellModel.AppSection.banners` + `showBanners()`; "Banners"-rij in
[LeftNavView](Avatar2/Features/Shell/LeftNavView.swift) onder Portraits; `ShellView.mainArea`
rendert de gallery bij `section == .banners`.

## 35.3 — BannersGalleryView
- status: done
- owner: FEAT (2026-06-25)

**Result:** [BannersGalleryView](Avatar2/Features/Banners/BannersGalleryView.swift) — wijde
banner-tegels (grid), "Upload banner" (NSOpenPanel), "Start from a gradient"-preset-rij
(rendert via `BannerCompositor` naar 1600×500 PNG), rechtsklik rename/delete, empty-state.

## 35.4 — Preview → saved-banner chooser
- status: done
- owner: FEAT (2026-06-25)

**Result:** [BannerChooser](Avatar2/Features/SocialPreview/BannerChooser.swift) vervangt de
oude inline `BannerPanel` in de preview: "Match avatar" (default) + grid van opgeslagen
`Banner2` (kiezen kopieert de bytes → `setBannerBackground(.image)`, undo'baar) + "New banner"
→ Banners-sectie. (`BannerPanel.swift` verwijderd — niet meer gebruikt.)

## 35.5 — Editor-breadcrumb → Portraits
- status: done
- owner: FEAT (2026-06-25)

**Result:** [LibraryBreadcrumb](Avatar2/Features/Portraits/LibraryBreadcrumb.swift): het
`.home`-broodkruim wijst nu naar "Portraits" i.p.v. "Home".

---

## E34-feedback-ronde — UI-refinements (done, 2026-06-25)
Bij dezelfde ronde aangepast in de social-preview (E34):
- **Full-screen:** de preview is nu een overlay op VENSTERNIVEAU ([ShellView](Avatar2/Features/Shell/ShellView.swift)) — left-nav valt weg.
- **Preview-knop:** gelabelde pill ("Preview" + oog) op Share-hoogte i.p.v. een abstracte icoon-knop ([ShellTopBar](Avatar2/Features/Shell/ShellTopBar.swift)).
- **Platform-logo's:** Phosphor merk-glyphs (LinkedIn/X/Instagram) in een slanke navbalk per mockup ([PlatformChrome](Avatar2/Features/SocialPreview/PlatformChrome.swift)).
- **Rustiger UI:** scheidingslijnen weg (preview-header + control-kolom + de left-nav-trailing-lijn in de editor), preview-achtergrond = `Background.app` (geen aparte inset-band).
- **Zwevende control-kaart:** de rechter banner-kolom is een afgeronde kaart met lucht rondom (zoals de left-nav).
