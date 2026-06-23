# Codebase audit — 2026-06-23 (security / performance / dead code)

Scope: `Avatar2/`, `AvatarUI/Sources/`, `AvatarKit/Sources/` (v2 surface). v1 `Avatar/`,
`backend/`, `admin/`, `website/` excluded. Three parallel audits (security, performance,
dead/inefficient code), all findings grep-verified.

Overall the codebase is in good shape — security core (AES-GCM session encryption, Keychain
key, correct TLS pinning, locked-down ATS + sandbox + hardened runtime, no hardcoded secrets)
is well-built, and prior cleanup passes left little dead code. No critical/high security issues.

---

## 🔄 "Do all the rest" — progress log (started 2026-06-23)

- ✅ **S1** (URL scheme guard, all 3 sites via shared `URL.isAllowedExternalScheme`) — done.
- ✅ **S2** (plaintext-session fallback removed + test flipped) — done.
- ✅ **Dead code**: deleted `CreditMeter.requiresCloud` + its test (tautology), `ProTier.displayName` (unused, single-tier). **Kept** `CreditMeter.canAfford` + `SetLightingNormalizer.Stats.luma` — both are tested, sensible helpers (luma backs a real brightening assertion), not dead.
- 🗂️ **DS-surface "dead" items consolidated into ONE decision** (see "DS pruning — single decision" below): typography tokens (`h6`/`letterSpacingNormal`/`paragraphSpacingBase`), `DSQuotaBadge`, `DSInlineEditLabel` (362 lines, superseded by `RenameSheet` for portrait-rename but is a general inline-edit primitive), `DSMessageBanner`/`DSPanelHeader`/`DSGated`/`DSFeatureIndicator`, `DSMotion` tokens, `DSShadow.spread`, `DSIcon` registry cases. **Not deleted** — these are forward-built, tested, Figma-traceable DS API; pruning them is a deliberate call, grouped for you.
- ⏭️ **Skipped (intentional scaffolding, would undo deliberate work):** D1 `resetToActualSize` (WIP stub for story 27.2/27.3), D2 `onCrop`/`onFixAngle` (planned framing tools), D4 `onColorise`/`onRestoreBody` (planned AI features), D8 `freeCutouts*` (protocol stability), D13 Announcement stack (used by live v1).
- ✅ **Perf P1** — slider preview now renders off-main (cached source CGImage + 12ms debounce + cancel-stale), full-res preserved, neutral shows raw instantly. `EditColorPanel.swift`.
- ✅ **Perf P3** — live editor canvas `.high`→`.medium` interpolation (matches board E27.6). `EditorCanvasView.swift`. *Quality note: one-line revert if you find the focused subject too soft when zoomed in.*
- ✅ **Perf P5** — `ShellModel.hasTransparentCorners` no longer unpacks the full ~16MB bitmap; samples 4 corners via 1×1 contexts.
- ✅ **Perf P7** — `EffectsModel` keeps a parallel `pngCache` (encoded once per effect); `persist()` copies it instead of re-PNG-encoding the whole cache on every toggle. Identical persisted bytes.
- ⏭️ **Perf P4 & P6 skipped** — both are O(n)-per-frame over the node list; negligible at realistic counts (dozens), and a correct fix needs a spatial index / cross-pass cache (architecture change). Defer until node counts grow. Flagged, not done.
- ✅ **R1** — extracted `DSButtonLabel` (shared icon+title body); DSPrimaryButton/DSNeutralButton/DSGhostButton use it.
- ✅ **R2** — added `DSColor.neutralSurface(pressed:hovering:base:)`; replaced the 6 inline ghost-surface ladders (DSGhostButton, DSIconButton, DSToolButton ×2, DSBottomToolbar ×2, DSHover) — outputs provably identical.
- ✅ **R3** — one shared `Double.clamped01` (new `Numeric+Clamp.swift`); removed the DSToast + DSColorPicker copies. 31 AvatarUI tests green.
- ✅ **R4** (safe part) — `ShellModel.pngData(from:)` removed; 3 call sites now use the shared `NSImage.pngData()` (the dedup `NSImage+PNG.swift` was built for but missed). The `cgImage(from:)`/hex helpers left as-is (divergent signatures `UInt32`/`String`, mostly inline — the "not mechanical / low value" part the audit itself flagged).
- ✅ **D3** — removed the inert, redundant "Update notifications" toggle from Preferences + the orphan `updateNotificationsKey`. About/Updates already owns auto-check (live on Sparkle). Figma divergence documented in-code per your "remove the row" authorization.
- ✅ **P8** — `ThumbnailStore` keys on the full identifier instead of its 64-bit `hashValue` (no collision risk; still session-stable).
- ✅ **P2** — `EditorView` memoizes `decodedCutout`/`decodedOriginal`/`decodedBackground` in `@State`, refreshed on `updatedAt`/`persistentModelID` change + onAppear, instead of re-decoding `NSImage(data:)` on every body pass (`originalImage` was hit ~7×/pass). Invalidation uses the same `touch()` contract ThumbnailStore relies on (verified: `setBackground` touches, cutout paths touch, `originalData` is import-only).

---

## ✅ LOOP COMPLETE (2026-06-23)

**Done** (all verified: Avatar2 + v1 build, AvatarUI 31 + AvatarKit 52 tests green):
S1, S2 · dead-code (`requiresCloud`+test, `ProTier.displayName`) · perf P1, P2, P3, P5, P7, P8 · duplication R1, R2, R3, R4(safe part) · D3.

**Consciously deferred (with rationale, NOT done):**
- **Perf P4, P6** — O(n)-per-gesture-frame over the node list; negligible at realistic counts, correct fix needs a spatial index / cross-pass cache (architecture change). Revisit when node counts grow into the hundreds.
- **Dead-code D1, D2, D4, D8, D13** — active-WIP stub / planned roadmap UI / wire-compat / live-v1 usage. Removing would undo intentional work.
- **DS-surface pruning — DECIDED (Thierry, 2026-06-23): KEEP as ready-to-use DS API.** The unused-but-forward-built/Figma-traceable AvatarUI surface (typography tokens `h6`/`letterSpacingNormal`/`paragraphSpacingBase`, `DSQuotaBadge`, `DSInlineEditLabel`, `DSMessageBanner`/`DSPanelHeader`/`DSGated`/`DSFeatureIndicator`, `DSMotion` tokens, `DSShadow.spread`, `DSIcon` registry cases) stays. It is intentional forward-built design-system surface, **not dead code** — future dead-code audits should NOT re-flag unused AvatarUI DS API for deletion.
- **Kept tested helpers:** `CreditMeter.canAfford` (+test) and `SetLightingNormalizer.Stats.luma` — sensible, tested, contract-fitting (luma backs a real brightening assertion); not dead.
- **R4 remainder** — `cgImage(from:)`/hex helpers (divergent signatures, low value).

Nothing committed — all changes are in the working tree alongside your existing E27 edits.
**Suggested when you're back:** a quick visual smoke of the editor — the colour-slider live preview (P1, now off-main) and the canvas interpolation (P3, `.high`→`.medium`) are the two changes worth eyeballing.

Verification cadence: every batch → `xcodegen generate` + Avatar2 build + AvatarKit tests (+ v1 build for shared-code changes). All green so far.

---

## ✅ Already fixed (safe, mechanical — done this session, all targets build + tests green)

| # | File | Change |
|---|------|--------|
| 1 | `Avatar2/Features/Editor/EditorActionList.swift` | **Deleted** — fully dead (97 lines, header comment lied; zero refs repo-wide) |
| 2 | `AvatarUI/.../Components/DSZoomHUD.swift` | Deletion confirmed (was already removed on disk; project regenerated) |
| 3 | `Avatar2/Features/Settings/SettingsRootView.swift` | Removed dead `SettingsPlaceholderPage` |
| 4 | `Avatar2/Features/Editor/CanvasCamera.swift` | Removed dead `isIdentity` + unused `import SwiftUI` (CoreGraphics already imported) |
| 5 | `Avatar2/Features/Shell/ShellView.swift` | Removed dead private `portrait(_:)` |
| 6 | `AvatarUI/.../Components/DSPanelSurface.swift` | Removed abandoned `dsEdgeFade` modifier (deliberately dropped per DSEditPanel comment) |
| 7 | `Avatar2/Avatar2App.swift` | **Security**: guard CMS message CTA URL to `http`/`https`/`aaavatar` schemes before `NSWorkspace.open` (untrusted CMS input could open arbitrary scheme) |
| 8 | `AvatarKit/.../Backend/TLSPinning.swift` | Replaced production `print()` on pin-failure with `os.Logger().error` (stdout is invisible for a shipped .app; Logger routes to the unified log, matching the stated "production diagnostics" intent) |

Verified: `xcodegen generate` → **Avatar2 builds**, **Avatar (v1) builds**, **AvatarKit 53 tests pass**, **Avatar2 28 tests pass**.

---

## ⏸ Needs your input

### Security (defense-in-depth)

- **S1 — Stripe URLs opened without scheme guard.** `Avatar2/Features/Paywall/EntitlementModel.swift:152` (`openManageSubscription`) and `:305` (`openCheckout`). Same `NSWorkspace.open` sink as the CMS fix, but these URLs arrive over the **TLS-pinned, authenticated** backend channel (much higher-bar threat model), and it's the billing path. **Recommend**: apply the same `http`/`https`/`aaavatar` scheme guard at all three sites via a shared tiny helper (e.g. `URL.isAllowedExternalScheme`) rather than three inline copies. Left for your nod because it touches the payment flow.
- **S2 — Plaintext-session migration fallback.** `AvatarKit/.../Auth/AuthSessionFileStorage.swift:62-65` + `AuthSessionEncryption.swift:58-65`. `retrieve` accepts any non-encrypted file starting with `{`/`[` as a valid plaintext session and re-encrypts it. A local attacker with app-container write access could plant a forged session JSON. **Bounded impact**: the token is a Supabase JWT validated server-side (forged → 401), and exploiting needs container write access already. The plaintext path is a v1→v2 migration leftover that "shouldn't happen in 2.0" per its own comment. **Recommend**: drop the plaintext-acceptance branch (return nil / delete the file if not `0x01`-prefixed). Small behavior change → confirm no real 2.0 install relies on silent migration.

### Performance (image-editing hot paths)

- **P1 (HIGH) — Slider preview renders full-res on the main thread.** `Avatar2/Features/Editor/EditColorPanel.swift:149`: `.onChange(of: value) { onPreview(adjusted()) }` runs `CIContext.createCGImage` on a ~2048px cutout on the main thread, continuously while dragging. Stutters the whole adjust UX. **Recommend**: render off-main + debounce/cancel-in-flight, or precompute a canvas-sized `previewSource` once on appear and adjust against that. Mirrors the existing `ThumbnailStore`/`decodeCanvas` off-main pattern.
- **P2 (HIGH) — Repeated `NSImage(data:)` decodes in `EditorView` body.** `Avatar2/Features/Editor/EditorView.swift:165/174/234`: `originalImage`/`rawCutout`/`backgroundLayer` are plain computed properties that decode on every `body` pass (pan/zoom/hover/selection re-render); `originalImage` is read ~6× per pass → up to 6 decodes/render. **Recommend**: memoize keyed on `updatedAt` (ThumbnailStore-style) and dedup within a pass (decode once, pass down).
- **P3 — Live canvas re-resamples at `.high` every pan frame.** `Avatar2/Features/Editor/EditorCanvasView.swift:109-115`. The board already dropped to `.medium` (E27.6 Tier 4). **Decision needed**: this is the *primary editing surface* — `.medium` is a quality/perf tradeoff on the image the user is focused on. Drop to `.medium` (or only while actively panning)? Your call on the quality side.
- **P4 — `ShellModel`/`BoardView` op paths decode + `CGContext` on MainActor.** `ShellModel.swift:244/267-269/333` (`storeEffectResult`, `hasTransparentCorners` allocates a full bitmap to read 4 corner pixels), `BoardView.flipNode/retouchNode` (`:783/:800`), `matchLightingSelection` (`:647-668`, loops the selection synchronously). The engines themselves are off-main, but these op paths didn't get the E27.7 treatment. **Quick win (safe)**: `hasTransparentCorners` can use the 1×1-context corner-sampling trick already in `EditorCanvasView.isOpaqueAtNormalizedPoint` (`:382`) instead of materializing the whole bitmap. The rest = move off-main (needs care re: ordering/cancellation).
- **P5 — `EffectsModel.persist()` re-encodes the whole effect cache to PNG on every toggle.** `Avatar2/Features/Editor/EffectsPanel.swift:159-166`: `compactMapValues { $0.pngData() }` re-PNG-encodes *all* cached effect images on each toggle/selectNone, on the main actor. **Recommend**: store the encoded PNG alongside the NSImage in the cache so persist is a dict copy, or only re-encode the dirty entry.
- **P6 — `BoardView` repeated O(n) filters in body.** `BoardView.swift:39-42/77-79/245/263/348-350`: `selectedNode`/`selectedPortraits`/layout targets re-evaluate `portraits.filter/.first` each render. **Recommend**: cache `selectedPortraits` per body pass; build a `[PersistentIdentifier: Portrait2]` lookup once in `assignInitialLayout` instead of 3 separate filters.
- **P7 — `BoardView` marquee / `visibleNodes()` are O(n) per gesture frame.** `BoardView.swift:261-266/281-289`. Fine for dozens, degrades at hundreds during active drag (code already flags grid-bucket index as the fix). Defer until node counts justify it.
- **P8 (minor) — `ThumbnailStore` keys on `persistentModelID.hashValue`** (`ThumbnailStore.swift`) — theoretical hash-collision risk across many nodes. Key on the id's `description` instead. Low priority.

### Dead / inert code (judgment — kept because intentional-or-not is unclear)

- **D1 — `CanvasCamera.resetToActualSize()` is byte-identical to `reset()`** (`:79` vs `:29`), so ⌘0 ("100%") and ⇧⌘1 ("Fit") do the same thing. Documented stub for pixel-true 100% (story 27.2/27.3). Collapse now, or keep the stub until that story lands? (Touches the active canvas-zoom WIP.)
- **D2 — `CanvasActionToolbar.onCrop` / `onFixAngle`** (`:40-42/149-150`) are rendered as menu rows but never passed by any call site → always disabled dead UI. Wire them or delete the rows + params (keep `showFramingActions`/`showGrid`).
- **D3 — `updateNotifications` toggle is inert.** `SettingsPreferencesPage.swift:22` + `SettingsModel.swift:61` persist it but nothing reads it; the comment "wordt door 15.4 geconsumeerd" is false (About page uses Sparkle's own `automaticallyChecksForUpdates`). Wire to Sparkle or remove the row + key.
- **D4 — `onColorise` / `onRestoreBody`** (`EditColorPanel.swift:26/29` → `EditorView.swift:397/400`) only trip the paywall gate and make no backend call — "Colorise"/"Restore body" chips are no-ops behind the gate. Intentional placeholders? Confirm/track.
- **D5 — Dead typography tokens** `DSTextStyle.h6`, `letterSpacingNormal`, `paragraphSpacingBase` (`DSTypography.swift:48/50/84`) — zero refs, but they mirror Figma variables. Per the "tokens come from Figma 1:1" rule, keep as a complete mirror or trim to what's used? (Left untouched for this reason.)
- **D6 — `DSQuotaBadge`** (`DSBadge.swift:81`) — unused thin wrapper over `DSBadge(type:.brand)`. Delete, or keep as ready-to-use DS API?
- **D7 — Public AvatarKit API used only by its own tests:** `ProTier.displayName` (`EntitlementModels.swift:30`), `CreditMeter.requiresCloud(for:)` (`:51`, tautology — always true) and `canAfford(_:creditsRemaining:)` (`:65`), `SetLightingNormalizer.Stats.luma` (`:22`). Delete each + its test, or keep as public contract?
- **D8 — `AccountPayload.freeCutoutsUsed`/`freeCutoutsRemaining`** (`EntitlementModels.swift:135-136`) — decode-only, never read; comment says kept "for protocol stability." Confirm intentional.
- **D9 — `DSMotion` tokens barely adopted** — `micro`/`emphasis`/`springSmall`/`springTransform`/`reduceMotionEnabled` unused; DS components hardcode `.easeOut(duration:)` literals. Adopt the tokens or trim them?
- **D10 — `DSShadow.spread`** (`DSLayout.swift:103`) — stored but no consumer (SwiftUI has no shadow spread). Effectively dead field.
- **D11 — `DSIcon.Symbol`** has many defined-but-unmapped cases; `DSIcon.Weight` never used non-default. Intentional semantic registry, or trim?
- **D12 — Whole DS components referenced only by tests:** `DSInlineEditLabel` (362 lines, superseded by `RenameSheet`), `DSMessageBanner`, `DSPanelHeader`, `DSGated`+`DSFeatureIndicator`. Keep as DS surface or delete?
- **D13 — Announcement stack** (`Announcement`, `AnnouncementBadge`, `BackendClient.fetchPendingAnnouncement/fetchBadges/markAnnouncementSeen`) — zero refs in v2 (uses `Message`/`MessagingService`), but **actively used by frozen v1** `Avatar/`. Live shared code — only dead once v1 is dropped. Coupling note, not a deletion candidate yet.

### Duplication worth consolidating (refactor — needs a home decision)

- **R1** — DS button label body (icon + `Text` HStack) duplicated verbatim 3×: `DSPrimaryButton.swift:46-56`, `DSNeutralButton.swift:31-41`, `DSGhostButton.swift:32-42`. Extract `DSButtonLabel`.
- **R2** — Ghost-surface background ladder (`isPressed→neutralStrongest / isHovering→neutralStronger / else .clear`) duplicated 6×: `DSIconButton.swift:99`, `DSGhostButton.swift:75`, `DSToolButton.swift:145`, `DSBottomToolbar.swift:261 & :309`, `DSHover.swift:26`. Embedded in different ButtonStyles → needs a shared modifier decision.
- **R3** — `clamp01` duplicated: `DSColorPicker.swift:226` (`clamp01`) and `DSToast.swift:94` (`Double.clamped01`). Consolidate into one DS extension.
- **R4** — PNG/CGImage helpers re-implemented in Avatar2: `ShellModel.pngData(from:)` (`:577`) duplicates shared `NSImage.pngData()`; `SidebarView.swift:380` + `PortraitExporter.swift:199` re-implement `cgImage(from:)`/hex-parse also in `BackgroundKit.swift:174`. Signatures differ → not purely mechanical.
