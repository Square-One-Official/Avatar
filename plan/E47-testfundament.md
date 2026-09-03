# E47 — Testfundament kritieke paden

Team: **INFRA + FEAT**

Voortgekomen uit de CTO-audit (`plan/AUDIT-CTO-2026-07-01.md`, bevinding D1). De twee
bugs die deze audit vond (B1 grayscale-import, A2 generate-background-decode) waren
elk met één gerichte test gevangen — het patroon bestaat al
(`MessagingServiceTests.testMessageDecodesBackendShape`). De grootste gaten liggen
precies waar vandaag pijn ontstond: Paywall/`EntitlementModel`, `BackendClient`-decoding,
Board, SocialPreview, Share hebben **nul** tests.

---

## 47.1 — BackendClient protocol-seam + fixture-decode-tests per endpoint
- status: done
- team: INFRA
- blockedBy: —
- Result: URLProtocol-stub als seam (BackendClient's `session`-init-parameter
  bestond al; enige productiewijziging is de interne
  `resultDownloadSessionOverride`-testhaak voor de generate-background-
  result-download). Nieuw: `BackendStubURLProtocol.swift` (routetabel op pad,
  dekt óók de Storage-PUT van uploadInputPNG) + `BackendClientDecodeTests`
  met 12 tests: account (incl. dev-unlimited), import-claim (incl. pro-
  short-circuit), stylize (incl. dimensieloze respons — A2-les), upscale,
  colorize, generate-background (incl. tweede-hop-download), en de error-
  mappings 402→noCredits, 403 pro_required→proRequired, 401→unauthorized.
  Fixtures 1:1 op de 200/402-vormen uit backend/api/v1/*.ts.
  `swift test` AvatarKit: 71 tests groen.

**Wat:** `BackendClient` is een concrete `final class` zonder protocol-seam →
niet stub-baar in tests; de enige bestaande test
(`BackendClientBaseURLTests`) dekt alleen URL-resolutie. ~10 endpoints (account,
stylize, upscale, generate-background, feature-flags, …) hebben geen
decode/error-mapping-tests.
**Voorstel:** een smal `BackendProviding`-protocol (of `URLProtocol`-stub) zodat
requests injecteerbaar worden; per endpoint een fixture-JSON-test die het
Swift-model tegen een echte/voorbeeld-responsvorm decodeert, plus een 402→
`.noCredits`-mapping-test. Volg het patroon van `MessagingServiceTests.
testMessageDecodesBackendShape`.
**DoD:** minstens generate-background, stylize, upscale, colorize, account hebben een
decode-test; `swift test --package-path AvatarKit` groen; Result-regel.

## 47.2 — EntitlementModel-testsuite
- status: done
- team: FEAT
- blockedBy: 47.1 (heeft de protocol-seam nodig om te stubben)
- Result: `EntitlementModel.init` kreeg de minimale seam `backendSession:
  URLSession = TLSPinning.pinnedShared` (default = exact wat BackendClient
  zelf al koos → geen gedragsverandering, call sites ongemoeid). Nieuw:
  `Avatar2Tests/EntitlementModelTests.swift` met 8 tests: free-cap
  (allowed:false én het echte 402-pad) → paywall, allowed → account-refresh
  + quotaSummary, transportfout blokkeert niet, dev-unlimited via
  `is_dev_unlimited`, flags-fetch faalt → allEnabled-fallback, flags-fetch
  slaagt → remote waardes, credits-refresh na gefaalde cloud-actie (5→0 +
  toast→paywall). **Bijvangst-bugfix:** `RemoteFeatureFlags` had expliciete
  snake_case-CodingKeys bovenop `.convertFromSnakeCase` (dubbele mapping) —
  élke /v1/feature-flags-decode faalde stil, dus CMS-flags deden nooit
  iets; CodingKeys verwijderd + decode-test in AvatarKit erbij.
  `xcodebuild test -scheme Avatar2`: 84 tests groen (1 pre-existing skip);
  builds Avatar/Avatar2 groen; `swift test` AvatarKit (72) + AvatarUI (37)
  groen.

**Wat:** de monetisatie-kern (`EntitlementModel.claimImport()`, 402-routing naar de
paywall, dev-unlimited, feature-flags-fetch) heeft 0% dekking; alleen AvatarKit's
`CreditMeterTests` (tarieven) bestaat.
**Voorstel:** 5-6 gerichte tests: free-cap bereikt, 402 → paywall-route, dev-unlimited
override, feature-flags-fetch faalt → `allEnabled`-fallback, credits-refresh na een
gefaalde cloud-actie.
**DoD:** nieuwe testsuite groen, gebruikt de 47.1-seam; Result-regel.

## 47.3 — ShellModel/Board/SocialPreview/Share-tests
- status: done
- team: FEAT
- blockedBy: 47.2 (done)
- promotie: gepromoveerd 2026-07-02, 47.2 done
- Result: alle vier gebieden ≥3 tests, op pure/statische paden of de
  47.1/47.2-stub-sessie (geen UI-tests). **ShellModel** (+6 in
  `ShellModelTests`): cutoutSignature deterministisch/content-gevoelig,
  import-gate op de cap (402-stub → paywall, canvas+store ongemoeid; batch-contract
  sinds E14.10: geen tegel vóór de gate, rest bewaard als pending set), select
  (directe selectie-state + async canvas-decode), effect-apply met
  cutout-resultaat (edit-bron gewist), vol resultaat (edit-bron + verse
  stempel → stale na cutout-terugdraai), applyIsolatedResult (geen tweede
  matting-pass; oude stempel vanzelf stale). **Board** (+5 in
  `BoardSelectionTests`): cmd-klik-toggle-semantiek incl. anker-verschuiving,
  via nieuwe pure seam `BoardView.toggledSelection` (gedragsgelijke extractie
  van `toggleNodeSelection`, patroon `rangeExtendedSelection`).
  **SocialPreview** (nieuw `SocialPreviewTests`, 8): PreviewTab→platforms-
  switch (enkel/All/uniek-per-tab), Instagram-zonder-cover, cover-ratios
  4:1/3:1, BannerResolver match-kleur + neutrale fallbacks. **ExportSheet**
  (nieuw `ExportSheetTests`, 6): álle vorm×maat-combinaties → exacte
  pixelmaat, circle/rounded-maskers (hoeken transparant, midden/rand opaak),
  square opaak-met-kleur en transparant-zonder-achtergrond, grootteschatting
  via tweede seam `ExportSheet.estimatedBytes` (pure extractie van de
  inline-berekening). Beide seams gedragsvrij en gedocumenteerd. Builds
  Avatar/Avatar2 groen; `xcodebuild test -scheme Avatar2` 154 tests groen
  (1 pre-existing skip); `swift test` AvatarKit 92 + AvatarUI 37 groen.

**Wat:** `ShellModelTests` heeft slechts 2 tests voor het drukste model van de app
(import, selectie, effect-apply, re-isolate, edit-source-staleness); Board,
SocialPreview en Share hebben 0 tests.
**Voorstel:** minimaal dekken: `cutoutSignature`-staleness in ShellModel,
board-multi-select-toggle-logica, SocialPreview-platform-switch, ExportSheet
vorm/maat-combinaties.
**DoD:** elk van de vier gebieden heeft minstens 3 tests; Result-regel.
