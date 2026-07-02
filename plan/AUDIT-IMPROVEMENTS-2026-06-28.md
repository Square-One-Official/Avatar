# Audit-verbeteringen — uitvoer-log (2026-06-28)

UX-behoudende code-verbeteringen uit de feature-audit, één story per feature.
Bron-audit: `~/.claude/plans/list-alle-bestaande-features-cached-toast.md`.
Verificatie per story: `xcodegen` (alleen bij file-add/-remove) + Avatar2 build + relevante tests.
Niets wordt gecommit tenzij Thierry erom vraagt. Alleen eigen files per pad stagen (v2-main draait parallel-sessies).

---

## Story 1 — Banners: render van de main-thread halen (Task #4)

**Doel:** de zware banner-compositie (`BannerDocRenderer.render`, CPU CGContext + CoreText) niet meer op de main-thread draaien tijdens live preview en thumbnail-bake. Pixels identiek; alleen vloeiender.

**Probleem:** `composedImage(_:)` is `@MainActor`, dus `render()` (de dure stap) liep op main. Alleen `BannerShaderRenderer.bake` (SwiftUI `ImageRenderer`) heeft écht main nodig. `bakeThumbnail()` deed bovendien een full-size render + PNG-encode op main.

**Aanpak (UX-neutraal):**
1. `BannerRenderInput: Sendable` — snapshot van wat `render` nodig heeft (size, layers, fill/logo-bytes, focal/zoom). `BannerDoc` is een SwiftData `@Model` (niet Sendable) → eerst op main snapshotten, dan pas off-main renderen.
2. `render(_ doc:)` API ongewijzigd (15× gebruikt door `BannerDocRenderTests`) — wordt een thin wrapper rond de nieuwe pure `render(_ input:)`.
3. `composedImageAsync(_ doc:) async` (`@MainActor`): snapshot op main → `render` off-main via `Task.detached` (resultaat in `SendableCGImage`, bestaand patroon uit `ThumbnailRenderer.swift`) → `bake` op main alleen als er shaders zijn → watermark off-main.
4. Call sites: `BannerStudioView.refreshPreview/bakeThumbnail`, `BannerPreviewView.refresh` → `composedImageAsync`. PNG-encode in `bakeThumbnail` ook off-main. Ongebruikte sync `composedImage(_ doc:)` verwijderen.

**Verificatie:** Avatar2 build + `BannerDocRenderTests` groen (render-contract ongewijzigd); visuele smoke van Studio live-preview.

**Status:** ✅ done — Avatar2 build groen; `BannerDocRenderTests` 13 + `ShaderEffectTests` 3 = 16/16 groen.

---

## Story 2 — Engine: PipelineRouter fallback-cascade (Task #2)

**Doel:** de 3-paden-cutout echt veerkrachtig maken — faalt de gekozen on-device engine tijdens `cutout`, dan de volgende beschikbare proberen i.p.v. de import afbreken.

**Probleem:** `PipelineRouter.cutout` koos één engine en liet een fout doorlopen → "Couldn't find a person", ook al had Vision (het vangnet) het wél gered. Comment beweerde "echte routeringslogica komt in E02" (E02 is done) — stale.

**Aanpak (UX-neutraal + kostenveilig):**
- `cutout` cascadeert over de **beschikbare** engines: voorkeur eerst, dan registratievolgorde (Vision is het vangnet). Happy-path identiek; alleen de faal-route wint veerkracht — consistent met het al-gedocumenteerde "valt terug op Vision".
- **Cloud/Replicate bewust NIET in de fallback-keten** (kost credits/entitlement) — blijft een expliciet pad via `BackendClient`. ShellModel registreert alleen [Vision, ORMBG], dus geen stille cloud-call.
- `engine(preferring:)` semantiek ongewijzigd (gedeelde `orderedAvailableEngines`-helper). Stale comment vervangen.
- `ShellModel` ongewijzigd (fallback is transparant via de router-API).

**Verificatie:** AvatarKit `PipelineRouterTests` (incl. 2 nieuwe: fallback-bij-fout + alle-falen-gooit) + Avatar2 build + v1 (`Avatar`) build (AvatarKit is gedeeld). Bestaande 5 router-tests blijven groen (API-semantiek behouden).

**Status:** ✅ done — Avatar2 build groen, v1 `Avatar` build groen, `PipelineRouterTests` 7/7 groen (`swift test`). Gewijzigd: `PipelineRouter.swift`, `PipelineRouterTests.swift`.
**Noot:** AvatarKit-tests draaien via `swift test` in `AvatarKit/`, NIET `xcodebuild test -scheme AvatarKit` (scheme heeft geen test-action; een `| tail` maskeert die fout).

---

## Story 3 — Portrait2: effectCache single-entry decode (Task #3)

**Doel:** `effectBackgroundData` niet langer de hele effect-cache laten decoderen om één entry te lezen.

**Probleem:** `effectBackgroundData` → `effectCache[key]` → `JSONDecoder().decode([String: Data])` base64-decodeert **élke** gecachte effect-PNG, alleen om de actieve op te halen. Zit in hot paths: `ThumbnailStore`, `PortraitsGalleryView`, `PortraitExporter`.

**Aanpak (UX-neutraal):** alleen de actieve entry uitpakken via `JSONSerialization` → `[String: String]` (base64), en uitsluitend die ene `Data(base64Encoded:)` decoderen. Identieke bytes; inactieve effecten worden niet meer gedecodeerd. Geen `@Model`-cache, geen migratie. `effectCache` (panel-pad, heeft alle entries nodig) blijft ongewijzigd.

**Verificatie:** Avatar2 build + `Portrait2Tests` + `EffectCutoutTests` groen.

**Status:** ✅ done — Avatar2 build groen; `Portrait2Tests` 2 + `EffectCutoutTests` 13 = 15/15 groen. Gewijzigd: `Portrait2.swift`.

---

## Story 4 — Banners: BannerDoc.layers decode-cache (Task #5)

**Doel:** de `layers`-getter niet meer bij élke toegang JSON laten decoderen (canvas/panels lezen 'm tientallen keren per render/gesture-frame).

**Aanpak (UX-neutraal):** `@Transient @ObservationIgnored` in-memory cache (`cachedLayers` + `cachedLayersKey`); getter geeft de gecachte waarde terug zolang `layersData` ongewijzigd is (byte-vergelijk ≪ JSON-decode), setter ververst de cache. `@ObservationIgnored` houdt de cache buiten SwiftUI-tracking → geen "state-tijdens-update". Setter-semantiek (alleen schrijven bij geslaagde encode + altijd `touch()`) behouden.

**Verificatie:** Avatar2 build + `BannerDocRenderTests` 13/13 groen (render leest `doc.layers` → oefent de cache). `@Transient @ObservationIgnored`-combo compileert in `@Model`.

**Status:** ✅ done — 13/13 groen. Gewijzigd: `BannerDoc.swift`.

---

## Story 5 — Export/preview compositing off-main (Task #12)

**Doel:** de portret-compositing (`PortraitExporter.makePNG`) niet meer op de main-thread laten lopen voor live previews (Export-sheet 256px, Social Preview 512px).

**Probleem:** `makePNG(for:)` is `@MainActor` en leest ~10 `Portrait2`-velden direct → de hele composite + PNG-encode blokkeert de UI tijdens preview-refresh.

**Aanpak (UX-neutraal):** Sendable `RenderInput`-snapshot (mirror van de gelezen velden) + pure `makePNG(_ input:)`; `makePNG(for:)` blijft byte-identiek (delegeert naar de pure functie → export/board ongewijzigd). Nieuwe `makePNGAsync(for:)` snapshot't op main en rendert off-main (`Task.detached`). `SocialPreviewView.refresh` + `ExportSheet`-preview gebruiken de async variant. `ExportShape`/`PortraitAdjust` → `Sendable`.

**Verificatie:** Avatar2 build groen, **geen nieuwe Sendable/concurrency-warnings** door deze wijziging (de 3 resterende zijn pre-existing: ShellModel KeyPath, BackgroundPanel/EffectsPanel NSCache). Geen unit-test voor de exporter; gedrag behouden via mechanische `portrait.X → input.X`-transform; alle ops off-main-veilig (gedeelde CIContexts, zoals `ThumbnailRenderer` al doet). Aanrader: runtime-smoke van export + social preview.

**Status:** ✅ done. Gewijzigd: `PortraitExporter.swift`, `SocialPreviewView.swift`, `ExportSheet.swift`, `Portrait2.swift` (PortraitAdjust Sendable).

---

## Story 6 — Portraits thumbnails (Task #10): al opgelost (grep-false-positive)

Bij het lezen van de échte code: `GalleryLens` én `ListLens` (én de grid) gebruiken **al** een gedeelde `PortraitComposite`-view die off-main rendert (`Task.detached` + `SendableImage`) en cachet op `(id, updatedAt, maat)` via `PortraitThumbnailRenderer.Spec`. De audit-bevinding ("elke lens rendert eigen thumbnails / rauwe `NSImage(data:)`") was een grep-aanname die niet klopt. **Geen wijziging nodig.**
> Optionele follow-up (niet gedaan, risico): `PortraitThumbnailRenderer` dupliceert de compositing van `PortraitExporter`; nu `PortraitExporter.RenderInput` bestaat, is consolidatie mogelijk — maar het raakt 2 kritieke render-paden, dus alleen met runtime-validatie.

**Status:** ✅ done (al voldaan).

---

## Bijstelling backlog na lezen van de échte code

Twee grep-gebaseerde audit-bevindingen blijken al opgelost in de huidige code:
- **#10** (Portraits thumbs) — al gedeeld + off-main + gecachet (zie hierboven).
- **#7 perf-deel** (ShellModel `NSImage(data:)` memoiseren) — de 8 decodes zitten in **actie-methodes** (apply-effect/isolate/store), niet in een per-render `body`. `decodeCanvas` is al off-main (`SendableNSImage`); `hasTransparentCorners` is al gefixt (P5). Memoiseren helpt hier niet. Resteert het **god-object-split** (pure onderhoudbaarheid).

**Resterend = grotendeels SwiftUI view-tree-herstructurering**, waarvan UX-neutraliteit NIET met build+unit-tests te garanderen is (animaties, gestures, focus, layout): #6 (canvas-decompose), #7 (ShellModel-split), #8 (EditorView-decompose), #9 (BoardView-split), #11 (state→model). Plus #9 Board-P4/P6/P7 (echte perf, maar in gesture-code) en #13 (diep-audit Settings/Paywall/Backend). Deze verdienen runtime-smoke / menselijke review i.p.v. blind in een autonome loop — zie checkpoint.

---

## Geconsolideerde validatie (alle wijzigingen samen) — 2026-06-28

- **Avatar2** build groen · **Avatar (v1)** build groen.
- **Avatar2Tests: 76 geslaagd** (1 skipped, 0 failures).
- **AvatarKit `swift test`: 59 geslaagd** (0 failures).

**Afgerond + gevalideerd (6):** #4 banner-render off-main · #2 PipelineRouter fallback · #3 Portrait2 effectCache · #5 BannerDoc.layers-cache · #12 export/preview off-main · (#10 al voldaan).
**Gewijzigde files:** `BannerDocRenderer.swift`, `BannerStudioView.swift`, `BannerPreviewView.swift`, `BannerDoc.swift`, `PipelineRouter.swift`, `PipelineRouterTests.swift`, `Portrait2.swift`, `PortraitExporter.swift`, `SocialPreviewView.swift`, `ExportSheet.swift`. (Niets gecommit.)

## Checkpoint — loop gepauzeerd op de veilige grens

Reden: de resterende items (#6, #7-split, #8, #9, #11) zijn **SwiftUI view-tree-herstructureringen**; build + unit-tests bewijzen daar GEEN UX-neutraliteit (animaties/gestures/focus/layout). Jouw harde eis is "zonder de UX te veranderen" → die items blind in een autonome loop draaien zou precies dat riskeren. #9 Board-P4/P6/P7 is echte perf maar zit in gesture-code; #13 is een diep-audit (onderzoek).

**Aanrader per resterend item:**
- **#6 / #8 / #9-split / #7-split** (decomposities) — doen mét runtime-smoke (app draaien, canvas/editor/board/banner-gesture testen). Veiligst als aparte, herziene PR's. ShellModel-split (#7) kan puur via `extension`-bestanden (model-code, geen view-risk) — laagste risico van de set.
- **#9 Board-P4/P6/P7** — echte perf-win; doen mét profiling/runtime-check van marquee + drag.
- **#11 Background state→model** — bescheiden, stilistisch; alleen met runtime-check van de generate-sheet.
- **#13 Settings/Paywall/Backend** — eerst diep lezen (geblokkeerde agents), dan gerichte UX-neutrale fixes.

---

## Story 7 — Diep-audit Settings / Paywall / Backend-Auth (Task #13)

Diep gelezen (de eerder geblokkeerde ⚠️-gebieden): `BackendClient` (903), `AuthService`, `AuthSession*`, `EntitlementModel` (357), `PrivacyGate`, `AIFeatureRegistry`/`AIFeature`, `PrivacyPreferences2`, `AIPrivacyTier`.

**Conclusie: deze lagen zijn solide; de grep-gebaseerde audit-zorgen houden geen stand.**
- `BackendClient.send` — nette getypeerde errors (401/402/429/403-pro), snake_case + iso8601 decode, transport-wrapping. **Retry/backoff bewust NIET toegevoegd:** cutout faalt expres snel om naar Apple Subject Lift terug te vallen → retry zou de faal-UX veranderen (niet UX-neutraal).
- Codable-"duplicatie": 4 image-endpoints delen dezelfde response-vorm; consolideren is cosmetisch en raakt een kritiek, niet-runtime-testbaar netwerk-pad → niet gedaan (risico > baat).
- `EntitlementModel.refresh()` is al de single-source en haalt account+flags **concurrent** (`async let`); gating via één `allowAIFeature`/`PrivacyGate`. Geen dedup/debounce nodig.
- Settings-privacy: `AIFeature`-enum is al de centrale bron (tier/cost/copy); `AIFeatureRegistry`/`PrivacyGate` zijn dunne facades; de `switch tier`-plekken zijn aparte legitieme concerns — geen duplicatie.

**Eén concrete UX-neutrale fix doorgevoerd:** `AuthService.signOut()` wist nu `accessToken`/`email` eager (spiegelt de eager-flip in `verifyCode` + `EntitlementModel.signOutAccount`'s eager `account = nil`). Voorheen bleef `isSignedIn` kort `true` na uitloggen tot de async `authStateChanges`-stream vuurde → flicker. Supabase's eigen sessie-signout blijft async; de stream bevestigt nil idempotent.

**Verificatie:** Avatar2 build groen · AvatarKit `swift test` **59/59** groen (incl. `AuthSessionStorageTests`) · v1 build (loopt). Gewijzigd: `AuthService.swift`.

**Status:** ✅ done (de ⚠️-caveat op deze gebieden vervalt — solide bevonden).

---

## Story 8 — Board P4: op-paths off-main (Task #9, "functional only")

Keuze Thierry: alléén de functionele winst (#9 P4 + #11), GEEN file-splits, GEEN #9 P6/P7 (door eerdere audit als verwaarloosbaar uitgesteld).

**Doel:** de board-op-paths die decode + render synchroon op de main-thread deden, off-main draaien (UI blijft responsief tijdens de operatie). Ordening/undo ongewijzigd.

**Aanpak (UX-neutraal):**
- `matchLightingSelection` — snapshot `(node, before-bytes)` op main; zware per-node match (decode + colorMatrix + PNG) in `Task.detached`; SwiftData-mutaties + undo terug op main. `SetLightingNormalizer.Stats` is Sendable, normalizer gebruikt thread-safe CIContext. Selectie/reference-volgorde behouden.
- `flipNode` / `retouchNode` — decode + render (CGContext-flip / `PortraitEnhancer.magicRetouch`) in `Task.detached` (resultaat via `SendableCGImage`); apply op main via `undoableApplyToNode`.

**Verificatie:** Avatar2 build groen + **Avatar2Tests 76/76** groen. Gewijzigd: `BoardView.swift`. (Aanrader: runtime-smoke van match-lighting/flip/retouch op de board.)

**Status:** ✅ done.

---

## Story 9 — Background state→model (Task #11): UITGESTELD (na volledige inspectie)

Na het volledig lezen van `GenerateBackgroundSheet` (615 LOC): #11 is **puur structureel** (testbaarheid/kleiner body — geen functionele/perf-winst). De 10 `@State` (`model`/`style`/`view`/`prompt`/…) worden ~60× door de view gebruikt, en de namen zijn alomtegenwoordige substrings (`model`→`BackgroundGenerationModel`/`availableModels`/`defaultModel`/`generationModel`; `style`→`styleStep`/`styleGrid`/`customStyleText`/`BackgroundGenerationStyle`). Een veilige move vergt ~60 context-gevoelige edits + `@Bindable`-bindings, op een wérkende AI-generatie-flow die ik niet runtime kan valideren, in een working tree die parallel-sessies delen.

**Uitgevoerd (op verzoek "Do 11"):** nieuwe `@Observable final class BackgroundGenerationForm` in hetzelfde bestand (zodat 'ie de private `GenerateBackgroundStep` kan gebruiken — `GenerateBackgroundStep` → internal). De 10 `@State` zijn vervangen door één `@State private var form`; alle ~40 referenties → `form.X` / `$form.X`. `usesCloudModel` + `canGenerate` (de testbare logica) verhuisden naar het model. Acties (`generate`/apple-bridge) bleven op de view (hebben `entitlement`/`context`/`onSaved`/`dismiss` nodig).

**Veiligheid:** na het verwijderen van de losse `@State` markeert de compiler élke gemiste referentie als "cannot find in scope" → de build is een volledig vangnet (geen stille misser). Bindings (`$form.prompt` e.d.) compileren = werken (Binding dynamic-member). Restrisico = runtime-binding-gedrag (standaard `@State`-of-`@Observable`-patroon) → runtime-smoke aangeraden.

**Verificatie:** Avatar2 build groen + **Avatar2Tests 76/76** + `BackgroundGenerationCatalogTests` 9/9 groen. Gewijzigd: `GenerateBackgroundSheet.swift`. (Aanrader: runtime-smoke — generate-sheet openen, style/prompt/model wisselen, genereren.)

**Status:** ✅ done.

---

## Eindstand uitvoer (2026-06-28)

**Geïmplementeerd + gevalideerd (8):** #4 banner-render off-main · #2 PipelineRouter fallback · #3 Portrait2 effectCache · #5 BannerDoc.layers-cache · #12 export/preview off-main · #13 deep-audit + `signOut` eager-clear · #9 Board-P4 op-paths off-main · #11 Background state→model.
**Al voldaan (1):** #10 Portraits-thumbs (`PortraitComposite`).
**Bewust niet gedaan (Thierry's "functional only"):** #6/#7/#8 + #9-split (reorganisatie-only, vergt access-verzwakking) · #9 P6/P7 (eerder uitgesteld als verwaarloosbaar — spatial-index architectuurwijziging).
**Status:** alle gewijzigde targets groen (Avatar2 + v1 build · Avatar2Tests 76 · AvatarKit 59). **Niets gecommit** — alles in de working tree.

---

## Story 11 — Code-review-fixes (na `/code-review` op de change set)

`/code-review` (3 finder-agents, inline verify) leverde 6 punten op; doorgevoerd + onderbouwde no-ops:

- ✅ **#1 (Med) — onDisappear-bake schreef naar mogelijk verwijderd @Model.** `bakeThumbnail` schrijft `doc.previewImageData` nu alleen als `doc.modelContext != nil` (na de awaits kan het doc verwijderd zijn). `BannerStudioView.swift`.
- ✅ **#2 (Low-Med) — stale bake kon verse preview overschrijven.** `bakeThumbnail` bailt nu bij `Task.isCancelled` ná render én ná PNG-encode (de debounce cancelt de vorige `thumbnailBakeTask`). `BannerStudioView.swift`.
- ✅ **#3 (Low) — `effectBackgroundData` parse'de elke read de hele JSON.** `@Transient @ObservationIgnored`-cache toegevoegd (sleutel = actief effect + bron-bytes), zelfde patroon als `BannerDoc.layers`. `Portrait2.swift`.
- ✅ **#6 (Low) — `BannerExport` dupliceerde de banner-composite + deed 'm op main.** `presentSavePanel` is nu `async` en gebruikt de gedeelde `composedImageAsync` (off-main, byte-identiek); eigen `composedImage`-helper verwijderd. Caller `ShellModel.exportCurrentBanner` → `await`. `BannerExport.swift`, `ShellModel.swift`.
- ⏭️ **#4 (Low) — signOut "resurrection" edge: NIET gefixt (bewust).** Een guard vergt een extra state-flag in de auth-stream tegen een race die Supabase's `signOut`-semantiek (prompte `.signedOut`) al voorkomt → net-negatief (complexiteit in gevoelig pad). De eager-clear is al een verbetering.
- ⏭️ **#5 (Low) — PortraitThumbnailRenderer ↔ PortraitExporter dup: GEEN drift-bug.** Geverifieerd: `if useOriginalBackground || portraitBlur` (thumb) == `if useOriginalBackground {…}; if blur {…}` (export) → pixel-identiek vandaag. Consolidatie is risicovolle refactor van 2 kritieke render-paden (niet runtime-valideerbaar) → aanrader als aparte herziene PR, niet blind.

**Verificatie:** Avatar2 build + Avatar2Tests (geen AvatarKit-wijziging deze ronde). Niets gecommit.


