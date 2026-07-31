# E42 — AI background generation

Team: **FEAT + INFRA + AI**

## 42.1–42.6 — Unified generate sheet + cloud backend
- status: done
- owner: agent (2026-06-28)

DS `GenerateBackgroundSheet` (model / style / view / prompt), `BackgroundImageKit` persist,
entry via Background panel, Banner studio, Manage backgrounds.

## 42.7 — Apple executor
- status: done
- owner: agent (2026-06-28)
- DoD: Apple model opens Image Playground from same sheet; result saved + applied

Tier 2: style/view hidden; **Continue** → native Image Playground sheet.
Tier 3: Gemini/OpenAI in-panel; Apple optional.

## 42.4 — Wide T2I bakeoff
- status: backlog
- blockedBy: — (deploy done)

Verify nano-banana vs gpt-image-1.5 on 1500×500 banner prompts (no people).
Default stays registry default until bakeoff logged here under **Result:**.

## Deploy checklist
1. `backend/api/v1/generate-background.ts` + `vercel.json` entry — done
2. Preview deploy → smoke POST with dev account — route smoke done (401/405); full gen needs authed dev user
3. Client `dev.apiBase` against preview optional

**Result:** Unified `GenerateBackgroundSheet` + `GenerateBackgroundPresenter` (stable host on `ShellView`, `interactiveDismissDisabled`, native `Menu` for model picker). Wired from editor/banner background panels + Manage Backgrounds. `BackgroundGenerationCoordinator` → `BackendClient.generateBackground`. Backend `/v1/generate-background` deployed prod 2026-06-28 (`dpl_WZUMTNz6Qi78232ty46DeRrnrq88`, alias `api.aaavatar.nl`); smoke: POST → 401, GET → 405. Preview: `avatars-942ycodp1-square-one-69d6814b.vercel.app`. Builds: Avatar + Avatar2 groen; `BackgroundGenerationCatalogTests` 6/6 groen; backend `tsc` groen. Style swatches = gradient placeholders (Figma assets nog open). 42.4 bakeoff nog backlog.
