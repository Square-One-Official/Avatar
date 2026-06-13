# E05 — Main app shell

Team: **FEAT**

Figma: App / First use, Dropzone, Image added, Isolating animation, Sidebar images.

## 5.1 — First use-empty-state
- status: done
- owner: FEAT
- blockedBy: E03.2
- DoD: beide targets bouwen, tests groen

Memoji-cirkel, gefixte copy, quota pas tonen ná eerste cutout.

Notities (FEAT, bij oplevering):
- Memoji-cirkel is een gedocumenteerde placeholder (cirkel + glyph): het echte memoji-beeld
  is een Figma-asset; exporteren zodra het "Aaavatar"-bestand in de Figma desktop-app open
  staat (MCP had nu een ander bestand voor zich).
- Quota-gating: EntitlementModel.hasCompletedFirstCutout (UserDefaults shell.firstCutoutDone);
  de status-strip verbergt de quota-badge tot markFirstCutoutCompleted() — aanroepen vanuit
  de import-flow (E05.2/5.3).
- Choose file… is een bewuste no-op tot E05.2 (import → PipelineRouter); INFRA-placeholder
  ContentPlaceholderView is vervangen door ShellView (waar 5.2–5.5 in haken).

**Result:** First-use-empty-state in Avatar2/Features/Shell/ (FirstUseEmptyState + ShellView-wortel): memoji-cirkel-placeholder, review-copy ("Drop a portrait — yours or a colleague's — or choose a file"), Choose file…-knop (no-op tot E05.2), quota-badge pas ná eerste cutout via EntitlementModel; beide targets bouwen groen, packagetests groen, smoke-run OK.

## 5.2 — Import
- status: done
- owner: FEAT
- blockedBy: E02.1, E03.3
- DoD: beide targets bouwen, tests groen

Drag-drop (heel venster als target) + bestandskiezer → PipelineRouter.

Notities (FEAT, bij oplevering):
- Router heeft alleen VisionCutoutEngine geregistreerd; ORMBG (download, E08.1) en cloud
  (entitlement) haken aan via hun eigen stories.
- Review-fix toegepast: heel venster is droptarget, dashed vensterrand-glow bij hover i.p.v.
  omlijnd vierkant. Bestandskiezer via NSOpenPanel (entitlement user-selected.read-write
  stond al goed).
- Processing-staat is minimaal ("Isolating…", origineel op halve opacity) — E05.3 levert de
  echte fade-out, statuscopy en klaar/faalstaat-polish. Faalstaat (geen persoon) bestaat al
  barebones met retry-knop.
- Geslaagde cutout roept EntitlementModel.markFirstCutoutCompleted() aan → quota-badge wordt
  zichtbaar (E05.1-besluit). Geen server-side claimImport in deze story (quota-handhaving
  hoort bij de echte free-tier-flow; noteren bij E13/release-hardening).
- End-to-end drop/kiezer handmatig testen kan pas met een echte foto-sessie; engine zelf is
  unit-getest in AvatarKit (E02.1).

**Result:** Import in Avatar2/Features/Shell/ (ShellModel + uitgebreide ShellView): drag-drop over het hele venster (fileURL- én image-providers, dashed rand-glow) en NSOpenPanel-bestandskiezer → PipelineRouter(Vision) → canvasstates empty/processing/result/failed; eerste cutout flipt de quota-gating; beide targets bouwen groen, packagetests groen, smoke-run OK.

## 5.3 — Isolating-animatie
- status: done
- owner: FEAT
- blockedBy: 5.2
- DoD: beide targets bouwen, tests groen

Achtergrond fade-out tijdens cutout + status op canvas ('Cutting out hair…'), incl. klaar- en
faalstaat.

Notities (FEAT, bij oplevering):
- Twee fasen conform de frames: Image added = volle foto (r-2xl) + pill "Removing
  background..."; Isolating animation = achtergrond fadet naar donker (app-achtergrondlaag
  animeert tussen origineel en cutout-overlay) + "Cutting out hair...".
- De "Logo container" in de Figma-pill exposeert geen asset; kleine activity-indicator als
  invulling (in de geest). Timing gedeeld via IsolatingTiming (view animeert, model wacht).
- Faalstaat blijft de bestaande copy + retry-knop (geen Figma-frame voor).

**Result:** IsolatingCanvas + IsolatingStatusPill in Avatar2/Features/Shell/ en ShellModel-state .revealing(original:cutout:): processing toont origineel + "Removing background...", cutout klaar → 0,8s zwartfade van de achtergrond onder de cutout-overlay + "Cutting out hair...", daarna .result → editor; status-pill = Figma "Recording" (capsule bg Card, 32-container met spinner, Labels/Small subtle, rechtsonder gap-4). Beide targets bouwen groen, alle tests groen (2 nieuwe Avatar2-tests: ShellModelTests).

## 5.4 — Sidebar (set)
- status: done
- owner: FEAT
- blockedBy: E03.5
- DoD: beide targets bouwen, tests groen

Bewerkte thumbnails (Figma-foto's zijn placeholders), naam/rol, zoek, add-knop (button-component).
Canvas-overgang zonder layoutshift. SwiftData-model Portrait2, los van v1-store.

Notities (FEAT, bij oplevering):
- Zoekveld is DSTextField (h40) als stand-in: de Figma "Search input"-component (h48, 6 states)
  ontbreekt in AvatarUI — DS-story E03.10 toegevoegd; vervangen zodra die landt.
- Images-tool in de toolbar = de sidebar-toggle (lime ring volgt de sidebar-staat, geen
  bottom-paneel); de avatar-toggle rechtsboven uit App / Edit komt met de export/topbar-iteratie.
- Naam/rol uit de header schrijven door naar het geselecteerde Portrait2 (didSet-proxy);
  geslaagde cutout → nieuw portret, meteen geselecteerd.

**Result:** Sidebar/set in Avatar2/Features/Sidebar/ (Portrait2 @Model met externalStorage-cutout + SidebarView 248 breed op bg Card: DSTextField-zoek, DSSidebarRow-slots met echte cutout-thumbs 48, DSAddButton onderaan) + ShellModel-uitbreiding (isSidebarVisible, select/persist, naam/rol-doorschrijf) en EditorView-interceptie van de Images-tool; sidebar schuift met één spring in (move-transition, canvas centreert mee — geen layoutshift); eigen modelContainer in Avatar2App, los van de v1-store. Beide targets bouwen groen, alle tests groen (2 nieuwe Avatar2-tests: Portrait2Tests).

**Result:** _(invullen bij done)_

## 5.5 — Name/Role-header
- status: done
- owner: FEAT
- blockedBy: E03.2
- DoD: beide targets bouwen, tests groen

Met inline edit.

Notities (FEAT, bij oplevering):
- Inline edit = plain TextFields in DS-typografie (naam h6, rol bodySmall) met muted prompts;
  header verschijnt alleen bij een portret op canvas (result-staat).
- Naam/rol leven nu op ShellModel (in-memory); verhuizen naar SwiftData-model Portrait2
  zodra E05.4 landt.

**Result:** PortraitHeader (naam/rol, inline edit via plain DS-TextFields) in Avatar2/Features/Shell/, gemount top-leading op het canvas in de result-staat; state op ShellModel tot Portrait2 (E05.4); beide targets bouwen groen, packagetests groen, smoke-run OK.


## 5.6 — Nudge: high-fidelity model na rafelig haarresultaat
- status: done
- owner: FEAT (AI-agent, marathon 2026-06-13)
- blockedBy: E15.2
- DoD: beide targets bouwen, tests groen
- Context: besluit Thierry 2026-06-12 (vervolg op de ORMBG-herziening); derde plek van de optionele model-download naast E04.6 (onboarding) en E15.2 (Settings > AI & Models). Zelfde OrmbgModelStore-state.

Detecteer ná een Vision-cutout een waarschijnlijk rafelig haarresultaat en toon subtiel bij
het resultaat een aanbod om het high-fidelity model te downloaden. Hard in de story:
**eenmalig per gebruiker**, wegklikbaar, géén modal. Detectie-heuristiek (bv. alpha-rafel
langs de bovenrand van het silhouet) is onderdeel van de story — afstemmen met AI-team
over een bruikbaar signaal uit de engine.

**Plan:**
1. HairEdgeHeuristic (Features/Editor, FEAT-lane — werkt op de cutout-output, geen
   AvatarKit-wijziging; een diepere engine-confidence kan dit later vervangen, notitie voor AI):
   pure functie isLikelyRagged(cutout:) — downsample, per kolom de bovenste opake rij zoeken,
   gemiddelde absolute sprong tussen buurkolommen / hoogte > drempel → rafelige (spikey)
   haarrand zoals Vision's semi-binaire matte die geeft. Unit-getest (glad vs gekarteld).
2. Nudge alleen wanneer: cutout kwam van de Vision-engine (niet al ORMBG/cloud), ORMBG níét
   geïnstalleerd, heuristiek = rafelig, én nog niet eerder getoond (UserDefaults one-time flag).
3. UI: subtiele inline banner bij het resultaat (geen modal), wegklikbaar (× → one-time flag),
   met "Download" die dezelfde OrmbgModelStore-download start (gedeelde state met E04.6/E15.2);
   na start verdwijnt de nudge.
4. Beide targets bouwen, tests groen, visuele smoke-run.

**Result:** HairEdgeHeuristic (Features/Editor, FEAT-lane): pure isLikelyRagged(cutout:) — meet de gemiddelde absolute top-randsprong tussen buurkolommen (genormaliseerd), drempel 0.02; semi-binaire Vision-haarranden scoren hoog, gladde randen ~0. 3 unit-tests (glad ≠ rafelig, ordering). ShellModel toont de nudge eenmalig (UserDefaults `nudge.hifiHairShown`) wanneer: Vision-engine gebruikt, ORMBG niet geïnstalleerd, rand rafelig. HairNudgeBanner (Features/Shell): subtiele niet-modale banner onderin ("Rough hair edges? … Download / ×"), wegklikbaar (× → one-time), Download start de gedeelde OrmbgModelStore-download + zet engine-voorkeur. Detectie werkt op de cutout-output; een diepere engine-confidence kan dit later vervangen (notitie AI). DEBUG-haak --force-hair-nudge. Smoke-run (ontgrendeld): banner subtiel onderin gerenderd. Beide targets bouwen groen, suite groen.

## 5.7 — "Align set"-actie in de sidebar
- status: done
- owner: FEAT (AI-agent, marathon)
- blockedBy: E06.5
- DoD: beide targets bouwen, tests groen
- Context: besluit Thierry 2026-06-13. GEEN Figma-afhankelijkheid (spec-bron in E06.4/6.5). Dit is de kern-merkbelofte als één knop — prominent maar niet schreeuwerig.

Spec (Thierry): past het auto-frame-profiel (E06.5) toe op álle portretten in de set, met
previewanimatie in de thumbnails; undo geldt set-breed als één stap.

**Plan:**
1. "Align set"-knop in de sidebar boven Add (DSPrimaryButton brand, wand-icoon) — prominent
   maar rustig; alleen zichtbaar bij ≥2 portretten (een set).
2. AutoFramer.transform(forCutout:) async (off-main Vision-detectie) per portret; betrekt de
   getunede E06.5/AutoAligner-doelwaarden, geen nieuwe.
3. Set-breed undo als één stap: alle transforms berekenen, dan binnen één
   NSUndoManager-groep (begin/endUndoGrouping) schrijven + registreren → één Cmd+Z draait
   de hele set terug.
4. Previewanimatie: korte thumbnail-puls (scaleEffect) tijdens het alignen; knop toont
   "Aligning…" en is disabled.

**Result:** "Align set"-knop (DSPrimaryButton brand + wand-icoon) in de sidebar boven Add, zichtbaar bij ≥2 portretten; past AutoFramer (E06.5) toe op álle portretten. Set-breed undo als één stap: transforms eerst (off-main, AutoFramer.transform(forCutout:)) berekend, dan binnen één NSUndoManager-groep (begin/endUndoGrouping) geschreven + geregistreerd → één Cmd+Z draait de hele set terug. Previewanimatie: thumbnail-puls (scaleEffect) tijdens align, knop toont "Aligning…"/disabled. DEBUG-haak --seed-set. Smoke-run (ontgrendeld): hero-knop prominent boven Add met geopende set-sidebar. Beide targets bouwen groen, suite groen.

## 5.8 — Topbar-randmarges op het venster-marge-token
- status: done
- owner: FEAT (AI-agent, marathon 2026-06-13)
- blockedBy: —
- DoD: beide targets bouwen, tests groen, visuele smoke-run
- Context: visuele punt Thierry (13 jun): het rechter topbar-cluster staat te ver van de vensterrand; trailing-padding moet hetzelfde token zijn als de venster-marge van sidebar/canvas — geen los magic number. Linkerkant meteen gecheckt.

**Plan:**
1. `ShellMetrics.windowEdgeInset` (= DSSpacing.gap1, de marge die E03.15 als kaart-vensterrand
   introduceerde) als één bron in Features/Shell/; SidebarView.edgeInset verwijst ernaar.
2. Gear-cluster trailing: 16 (magic) → windowEdgeInset, zodat de glascirkel uitlijnt met de
   sidebar-kaartrand; top blijft het strook-ritme (gap3).
3. Linkerkant gecheckt: de quota-x (76) is opgebouwd uit de OS-window-controls (≈68, vast bij
   hiddenTitleBar) + gap2 — geen tokenbreuk; als constante met die afleiding gedocumenteerd.
4. Visuele smoke-run vóór/na.

**Result:** ShellMetrics (Features/Shell/) met `windowEdgeInset` (gap-1, de E03.15-vensterrand) en `topBarLeadingAfterWindowControls` (68 OS-controls + gap-2, gedocumenteerde afleiding i.p.v. magic 76); gear-cluster trailing van losse 16 → windowEdgeInset (lijnt met de sidebar-kaartrand), SidebarView.edgeInset verwijst nu naar hetzelfde token; linkerkant gecheckt — OS-gebonden, geen tokenbreuk. Beide targets bouwen groen, tests groen, smoke-run: gear op de kaartrand-lijn.
