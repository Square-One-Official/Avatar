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
- status: ready
- team: INFRA
- blockedBy: —

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
- status: ready
- team: FEAT
- blockedBy: 47.1 (heeft de protocol-seam nodig om te stubben)

**Wat:** de monetisatie-kern (`EntitlementModel.claimImport()`, 402-routing naar de
paywall, dev-unlimited, feature-flags-fetch) heeft 0% dekking; alleen AvatarKit's
`CreditMeterTests` (tarieven) bestaat.
**Voorstel:** 5-6 gerichte tests: free-cap bereikt, 402 → paywall-route, dev-unlimited
override, feature-flags-fetch faalt → `allEnabled`-fallback, credits-refresh na een
gefaalde cloud-actie.
**DoD:** nieuwe testsuite groen, gebruikt de 47.1-seam; Result-regel.

## 47.3 — ShellModel/Board/SocialPreview/Share-tests (backlog)
- status: backlog
- team: FEAT
- blockedBy: 47.2

**Wat:** `ShellModelTests` heeft slechts 2 tests voor het drukste model van de app
(import, selectie, effect-apply, re-isolate, edit-source-staleness); Board,
SocialPreview en Share hebben 0 tests.
**Voorstel:** minimaal dekken: `cutoutSignature`-staleness in ShellModel,
board-multi-select-toggle-logica, SocialPreview-platform-switch, ExportSheet
vorm/maat-combinaties.
**DoD:** elk van de vier gebieden heeft minstens 3 tests; Result-regel.
