# Aaavatar 2.0 — Board

**Doel:** Aaavatar 2.0 bouwen naast de bestaande app (die blijft werken tot de grote update). Scope eerste versie: Onboarding + main app volledig; Settings/Export/Paywall barebones.

Bronnen: `~/Documents/Claude/Projects/Aaavatar/aaavatar-2.0-bouwplan.md` (volledig plan), `figma-design-review.md`, `pipeline-audit-2.0.md`. Figma is de design-bron (pagina "Stories" + "Components").

## Hoe dit board werkt (voor elke agent — LEES DIT EERST)

0. Begin elke sessie met het synchroniseren van `v2-main` (`git fetch` + verse `v2-main` in je worktree, of rebase) **vóór** je het board leest — plan-status leeft op `v2-main`, een oude checkout geeft een verouderd board-beeld.
1. Status leeft per story in het epic-bestand (`plan/E##-*.md`): `backlog` → `ready` → `in_progress` → `done`. Jij werkt alleen stories die `ready` zijn én geen open blockers hebben.
2. Claim een story door status op `in_progress` te zetten + je team in `owner`, in dezelfde commit waarin je begint. Eén story per team tegelijk (WIP-limiet 1).
3. `done` mag pas als de Definition of Done haalt: beide targets bouwen (`Avatar` én `Avatar2`), tests groen, één regel resultaat-samenvatting in de story onder **Result:**.
4. Ownership-grenzen: INFRA bezit `Avatar2/` scaffolding + `AvatarKit/`-services; DS bezit `AvatarUI/`; AI bezit `AvatarKit/Engines/` + EdgeBenchmark; FEAT bezit `Avatar2/Features/<naam>/`. Mis je iets buiten je grens → voeg een story toe bij het juiste team (status `ready`), ga zelf verder met iets anders.
5. `Avatar/` (de oude app) is verboden terrein behalve in stories gemarkeerd SHARED.
6. Branch per story: `v2/<epic>-<story-id>`, merge naar `v2-main` bij groene build. `main` blijft van v1.
7. Werk je parallel met andere agents: gebruik git worktrees (`.claude/worktrees/` bestaat al).

## Kolommen (overzicht — detail en status in de epic-bestanden)

| Epic | Team | Status |
|------|------|--------|
| [E01 Fundament](E01-fundament.md) | INFRA | **done** (1.1–1.15) |
| [E02 Vision-engine minimaal](E02-vision-engine.md) | AI | **done** (2.1–2.5); 2.6 (randkwaliteit lage res) backlog — de story stond al in het epic-bestand maar was zijn `##`-kop kwijt (gerepareerd 2026-07-12) |
| [E03 Design system](E03-design-system.md) | DS | **done** (3.1–3.19) |
| [E04 Onboarding 2.0](E04-onboarding.md) | FEAT | **done** (4.1–4.8) |
| [E05 Main app shell](E05-main-shell.md) | FEAT | **done** (5.1–5.8) |
| [E06 Editor-framework](E06-editor-framework.md) | FEAT | **done** (6.1–6.6) |
| [E07 Background](E07-background.md) | FEAT | **done** (7.1–7.2) |
| [E08 Barebones-flows](E08-barebones.md) | FEAT | **done** (8.1 → E15, 8.2–8.3) |
| [E09 Effects](E09-effects.md) | FEAT+AI | **done** (9.1–9.2); **9.3 done** (eigen effecten, gemerged 2026-07-31 — prod-uitrol wacht op Thierry: sql/015 + backend-deploy) |
| [E10 Clothes](E10-clothes.md) | FEAT+AI | **done** (10.1–10.4) |
| [E11 Hair](E11-hair.md) | FEAT+AI | **done** (11.1–11.2) |
| [E12 Light & Retouch](E12-light-retouch.md) | FEAT | **done** (12.1–12.2) |
| [E13 Release-voorbereiding](E13-release.md) | INFRA | **done** (13.0–13.6; 13.1 apart v2-kanaal + release-v2.sh, 13.2 v1-back-up-import, 13.3 → [GO-NO-GO-2.0.md](GO-NO-GO-2.0.md) met de zes gated go-stappen voor Thierry) |
| [E14 Monetization 2.0](E14-monetization.md) | FEAT+INFRA | **done** (14.1–14.7, incl. Stripe-webhook-shapefix); **14.9 done** (Pro-lijst via CMS-collectie `pro-access` — uitrol wacht op sql/018 + admin/backend-deploy); 14.8 backlog (credits-transparantie) |
| [E15 Settings volledig](E15-settings.md) | FEAT | **done** (15.1–15.7) |
| [E16 Apple Intelligence](E16-apple-intelligence.md) | AI | blocked — wacht op macOS 27-beta op dev-Mac |
| [E27 Canvas-viewport & board-camera](E27-canvas-viewport.md) | FEAT | **done** (27.1–27.11) |
| [E29 Multi-select & batch](E29-multiselect-batch.md) | FEAT+AI | **done** (29.1–29.5) |
| [E31 Toolbar-unificatie](E31-toolbar-unification.md) | FEAT+DS | **done** (31.1–31.8); follow-up "Restore body"-strings gedaan in E49.2 (op branch, merge pending) |
| [E32 Face beauty-acties](E32-face-beauty.md) | FEAT+INFRA+AI | **32.1 in_progress** (code klaar, deploy wacht op 32.0-bakeoff) |
| [E34 Social Preview & Banner](E34-social-preview.md) | FEAT+AI+INFRA | **done** (34.1–34.7); 34.8–34.10 AI-generatie backlog |
| [E35 Banners-bibliotheek](E35-banners.md) | FEAT+INFRA | **done** (35.1–35.5) — uitgebreid door E36–E40 |
| [E36 Home & gallery-IA](E36-home-gallery-ia.md) | FEAT+DS | **done** (36.1–36.5); 36.6 backlog (zoekveld) |
| [E37 Banner Studio (editor)](E37-banner-studio.md) | FEAT+INFRA+DS | **done** (37.1–37.15, 37.17–37.19); 37.16 PaperKit backlog — **besluit Thierry 2026-07-12: `bannersEnabled` blijft default uit tot er gebruikersvraag naar banners is** |
| [E38 Shaders-engine](E38-shaders-engine.md) | AI+DS+FEAT | **done** (38.1–38.4, Figma-stijl Metal-shaders; DoD hergeverifieerd 2026-07-02 na E37.19) |
| [E39 CMS banner-presets](E39-cms-banner-presets.md) | INFRA+FEAT | **done** (39.1–39.2; 39.1 afgerond met prod-verificatie + decode-tests, 2026-07-02) |
| [E40 Banner als portret-achtergrond](E40-banner-as-portrait-background.md) | FEAT | **done** (40.1–40.2; 40.1 gehard 2026-07-02 — linked-check nu via `BannerDeletion.isLinked`, E46-les) |
| [E41 Boost Resolution](E41-upscale-quality.md) | INFRA+FEAT | **done** (41.1–41.2, 41.4, 41.5 herzien: Boost = on-device gratis óf Topaz 3cr+6MP-cap; backend live op prod 2026-07-12, app gemerged) |
| [E42 AI background generation](E42-ai-background-generation.md) | FEAT+INFRA+AI | **done** (42.1–42.3, 42.5–42.7); 42.4 backlog (wide T2I bakeoff) |
| [E43 Backend-deploy-sanering & AI-achtergrond-herstel](E43-backend-deploy-sanering.md) | INFRA | **done** (43.1–43.2 + 43.5, prod uitgevoerd 2026-07-02); 43.3–43.4 backlog |
| [E44 Cloud-actie betrouwbaarheid](E44-cloud-betrouwbaarheid.md) | FEAT+INFRA | **done** (44.1–44.2, prod-deploy 2026-07-02); 44.3 backlog |
| [E46 Undo & bevestiging bij destructieve acties](E46-destructieve-acties.md) | FEAT | **done** (46.1–46.2); 46.3 backlog (undo/prullenbak bulk-delete) |
| [E47 Testfundament kritieke paden](E47-testfundament.md) | INFRA+FEAT | **done** (47.1–47.3, incl. RemoteFeatureFlags-decode-fix) |
| [E48 Swift 6-concurrency-pad](E48-swift6-concurrency.md) | INFRA | backlog (48.1–48.3) |
| [E49 Opruimronde 2026-07](E49-opruimronde-2026-07.md) | FEAT+AI+DS | **done** (49.1–49.4, gemerged naar v2-main 2026-07-12) |
| [E50 Team-sets verdiepen](E50-team-sets.md) | FEAT | **50.1 done** (map-acties + ⌘A per lens); 50.2 backlog (wacht op E52-merge — HomeView) |
| [E51 macOS 26-kansen](E51-macos26-kansen.md) | AI+FEAT | backlog (51.1–51.4) |
| [E52 CMS-media-performance](E52-cms-media-performance.md) | INFRA+FEAT | **52.1 done** (2026-07-02, live op prod); 52.2 backlog |
| [E53 UX-polish](E53-ux-polish.md) | FEAT+DS | **53.1 done** (polish-sprint P0's, 2026-08-01) · **53.3 done** (live AX-geverifieerd) · **53.6 done** (shell-chrome; was al gebouwd, nu geverifieerd + gesloten) · **53.7 done** (persistente presentatie) — **53.2 done** (UX1 + UX2: fit-to-window, userZoomed-guard en gedeelde zoom-chip); **53.4 done** (reduce-motion-sweep + guard in build-v2.sh); **53.5 done** (P1/P2-restlijst, 15 stories); **53.8 done** (Playground-sheet op ShellView-host); **53.9 done** (icoongrootte-tokens + guard) — **E53 compleet** |
| [E54 CMS-stijlreferenties voor Effects](E54-effect-stijlreferenties.md) | INFRA+AI | **54.1 + 54.2 done** (bakeoff 2026-07-12: refs verslechteren stijltrouw op nano-banana → default-flip afgeblazen, koppel-rijen losgehaald); 54.3 (tekst-distillatie) = de kansrijke vervolgroute, 54.4 backlog |
