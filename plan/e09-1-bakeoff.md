# E09.1 — Stijl-route bakeoff (drie-armig)

Datum: 2026-06-12 · Owner: AI · Status: rapport

## Opzet

**Armen** (alle drie via `model_override` op `/v1/stylize`, dev-only endpoint op een
Vercel-preview-deploy van branch `v2/E09-9.1` — de armen stonden nog niet in het
productie-MODEL_REGISTRY, dus de story-route "preview-deploy tot de volgende E13.0-port"
is gevolgd):

| key | Replicate-ref | opmerking |
|---|---|---|
| `nano-banana` | `google/nano-banana` | Gemini 2.5 Flash Image |
| `flux-2-pro` | `black-forest-labs/flux-2-pro` | multi-ref instruction edit |
| `gpt-image-1.5` | `openai/gpt-image-1.5` | native Replicate-billing (geen eigen OpenAI-key meer nodig, i.t.t. `gpt-image-1`); `input_fidelity=high`, `quality=high` |

**Referentie:** de bestaande fill-body-route (FLUX.1 Fill [pro], productie
`api.aaavatar.nl/v1/fill-body`) — die preserveert gezichtspixels fysiek via mask, en is
daarmee de identiteits-lat: een arm die zichtbaar meer identiteit verliest dan deze route
valt af, ongeacht stijlkwaliteit.

**Portretten** (5, EdgeBench-cutouts → geflattened op grijs door het endpoint, ≤1024 px):

| id | beschrijving | waarom |
|---|---|---|
| p1-man-beard | man ~45, baard, krullen, blauw overhemd | rimpels/tanden-edits, leeftijdskarakter |
| p2-man-longhair | jonge man, lang haar, sik, donkere belichting | belichting-fix, haar-edit |
| p3-woman-curly | vrouw, grote krullenbos, neutrale blik | haarvolume (cutout-stress), identiteit frontaal |
| p4-woman-smile | lachende vrouw, zichtbare tanden | tanden bleken |
| p5-man-headset | man, zijwaartse blik, headset | identiteit bij niet-frontale pose |

**Cases** (identieke prompts per arm; volledige prompts onderaan):

- 4 stijlen: `style-clay`, `style-wood`, `style-3d`, `style-scribble` (elk met expliciete
  identity-clausule in de prompt)
- 5 edit-cases: `edit-teeth` (tanden bleken), `edit-wrinkles` (rimpels verminderen),
  `edit-lighting` (belichting fixen), `edit-hair` (kapsel wijzigen), `edit-clothes`
  (kleding wijzigen)

Matrix: 3 armen × 9 cases × 5 portretten = 135 generaties + 5 fill-body-referenties.

**Beoordeling:** visueel per contactsheet (rij = portret, kolommen = input | arm1 | arm2 |
arm3), hard criterium identity-behoud t.o.v. input en de fill-body-lat; daarnaast
edit-gehoorzaamheid ("change nothing else"), stijlkwaliteit en faalgedrag (weigeringen,
timeouts). Sheets: `~/Documents/Claude/Projects/Aaavatar/e09-bakeoff/`.

## Status run

102/140 calls voltooid op 2026-06-12. **Gepauzeerd: Replicate-saldo op** (402
Insufficient credit; daarvóór al 6/min-throttle bij <$5). Compleet: 4 stijlen (60/60),
edit-teeth (14/15), edit-wrinkles (15/15), referenties (5/5). Deels: edit-lighting (8/15).
Open: edit-hair (0), edit-clothes (0). Naveegrun na top-up maakt de matrix af (driver
slaat bestaande bestanden over).

## Resultaten (voorlopig — stijlen + teeth/wrinkles compleet)

Patroon is consistent over de vier stijlen:

- **nano-banana** — identiteit vrijwel altijd intact (sterkste van de drie), maar de
  stijltransformatie is conservatief: bij clay/wood blijft het dicht bij een gefilterde
  foto. Bij 3d en scribble is de balans juist goed (stijl zichtbaar, persoon herkenbaar).
- **flux-2-pro** — de meest uitgesproken stijl (echte clay-figurine, houten buste), maar
  herkadert het beeld regelmatig (pose/crop kwijt), cartoonificeert gezichten en verliest
  identiteit het vaakst (p5 scribble werd een ander persoon; p1 clay kreeg cartoon-ogen;
  wood wordt een generieke buste). Voor edits het minst gehoorzaam aan "change nothing else"
  (verandert expressie).
- **gpt-image-1.5** — middenweg: stijl sterker dan nano, identiteit duidelijk beter dan
  flux-2. Bij wood de beste balans. Maar: kent geen match-input-aspect (alleen 1:1/3:2/2:3)
  en herkadert/zoomt daardoor zichtbaar bij afwijkende inputverhoudingen; traagste arm
  (~45–60 s bij quality=high) en duurste.

Edits (teeth compleet, wrinkles compleet, lighting 8/15):

- **edit-teeth**: opvallend — alle drie de armen "tonen" het resultaat door de mond te
  openen bij gesloten-mond-inputs; nano het minst (p3 bleef dicht), flux-2 het meest.
  Op p4 (zichtbare tanden) doen alle drie het netjes natuurlijk.
- **edit-wrinkles**: nano het meest gehoorzaam (subtiel, leeftijd/karakter intact, kader
  exact); gpt goed maar herkadert; flux-2 oké met lichte gezichtsdrift.
- **Referentie fill-body (productie)**: gezicht per definitie pixel-vast, maar de fill
  hallucineert op 2/5 portretten (telefoon in hand bij p2; donkere artefacten + pseudo-tekst
  bij p5) — de identiteits-lat zit dus op het gezicht, niet op de rest van het canvas.

## Aanbeveling per feature (voorlopig, af te ronden na hair/clothes)

- **Effects/stijlen (E09.2)**: nano-banana als default (identiteit is het harde criterium;
  3d/scribble overtuigend, clay/wood acceptabel maar vlak). flux-2-pro valt af op
  identity-drift ondanks de mooiste stijl. Overweging voor later: stijlsterkte van nano
  per stijl bijsturen met promptversterking i.p.v. modelwissel.
- **Retouch/edits (E12)**: nano-banana — beste "change nothing else"-gehoorzaamheid, geen
  herkadering, snel (~10 s). gpt-image-1.5 is kwalitatief vergelijkbaar op het gezicht maar
  herkadert en is 4–5× trager.
- **Haar (E11) / Kleding (E10)**: nog open — wacht op resterende 30 calls na top-up.
- **Tarief-implicatie (E14.3)**: als nano-banana overal default wordt, is het
  standaardtarief (4 cr) dekkend; gpt-image-1.5 als eventuele premium-arm (7 cr) heeft
  alleen zin als hair/clothes een kwaliteitssprong laat zien.

## Bijlage: prompts

- **style-clay** — "Transform this portrait into a claymation-style clay sculpture character: smooth modelling-clay skin with subtle hand-sculpted texture, soft studio lighting." + identity-clausule
- **style-wood** — "Transform this portrait into a hand-carved wooden figurine: visible wood grain, warm natural wood tones, slightly stylized carving." + identity-clausule
- **style-3d** — "Transform this portrait into a stylized 3D animated-film character render: soft skin shading, subtle subsurface scattering, gentle exaggeration of features." + identity-clausule
- **style-scribble** — "Transform this portrait into a loose hand-drawn scribble illustration: expressive sketchy ink lines, minimal flat colour accents, plain light background." + identity-clausule
- identity-clausule: "Keep the person's facial features, expression, hairstyle and clothing clearly recognizable so the person remains identifiable."
- **edit-teeth** — "Whiten the teeth naturally. Change nothing else about the image."
- **edit-wrinkles** — "Subtly reduce facial wrinkles and even out the skin while keeping natural skin texture and the person's age and character. Change nothing else about the image."
- **edit-lighting** — "Fix the lighting of this portrait: balanced soft studio lighting, neutral white balance, even exposure on the face. Do not change the person, pose or clothing."
- **edit-hair** — "Change the hairstyle to a short, neatly trimmed haircut in the person's natural hair colour. Keep the face, expression and clothing exactly the same."
- **edit-clothes** — "Change the clothing to a dark tailored business suit with a white shirt. Keep the face, hair, expression and pose exactly the same."

## Procesnotities (voor herhaalruns)

- Preview-deploy: `vercel deploy --yes --archive=tgz` vanaf worktree-root (project
  avatars-api, rootDirectory=backend). Preview-env miste `REPLICATE_API_TOKEN`,
  `SUPABASE_SERVICE_ROLE_KEY`, `DEV_UNLIMITED_EMAILS` — toegevoegd (sensitive, scope
  preview). Preview heeft Vercel Authentication aan: Protection-Bypass-for-Automation-secret
  aangemaakt, header `x-vercel-protection-bypass`.
- Dev-JWT scripted: GoTrue admin `generate_link` (service role) → `/auth/v1/verify` met
  `token_hash` → access token (1 h; driver ververst zelf).
- De cutout-ratelimiter (token bucket 3/6s per user) wordt GEDEELD tussen productie en
  preview (zelfde Upstash, zelfde prefix) — drivers moeten request-starts globaal spreiden
  (≥4 s) en met jitter backoffen, anders 429-spiraal.
- gpt-image-1.5 op `quality=high` zit geregeld >50 s → STYLIZE_TIMEOUT_MS=80s +
  maxDuration 90 in vercel.json.
