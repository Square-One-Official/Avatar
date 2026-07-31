# E54 — CMS-stijlreferenties voor Effects

Team: **INFRA** (Payload-veld + backend) · **AI** (bakeoff/tuning)

Voortgekomen uit wens (Thierry, 2026-07-04): per effect 1 of meerdere voorbeeld-afbeeldingen in
het CMS kunnen meegeven, zodat het gegenereerde effect echt de stijl van die voorbeelden volgt.

Context uit de audit (2026-07-04): E33 bevatte al halve plumbing voor één stijlreferentie —
`backend/lib/payload.ts` leest `styleReference` en `stylize.ts`/`replicate.ts` sturen die als
extra input-image mee — maar het veld bestaat niet in `admin/src/collections/Effects.ts`, dus het
pad is dood spoor. Bovendien vertelt de prompt het model nergens wélke afbeelding de persoon is en
welke de stijl; dat is het grootste kwaliteitslek. Alles in dit epic is CMS + backend — geen
app-release nodig (`/v1/effects`-contract blijft ongewijzigd, referenties blijven server-only net
als `prompt`).

---

## 54.1 — CMS-veld `styleReferences` + backend multi-referentie + prompt-rolclausule
- status: done
- owner: INFRA (2026-07-04)
- team: INFRA
- Result: volledig CMS→model-pad voor stijlreferenties (branch `v2/e54-54.1`, merge 886c262).
  `Effects.ts`: array-veld `styleReferences` (max 4 upload-rijen) met admin-uitleg over goede
  referenties + identity-bleed-waarschuwing. `payload.ts`: `styleReferenceUrls: string[]`
  (dood enkelvoudig `styleReference`-pad verwijderd), rijen zonder url geskipt. `stylize.ts`:
  `fetchStyleReferences()` — cap 3, parallel, verkleind via `thumbnailVariant(…, 1024, 85)`,
  10-min in-process data-URL-cache, soft-fail per referentie; `STYLE_REFERENCE_CLAUSE` wordt
  alléén aan de prompt geplakt als er echt referenties meegaan. `replicate.ts`:
  `styleReferenceDataUrls: string[]` in alle vier adapters (nano-banana, seedream, flux-2,
  gpt-image). `/v1/effects`-contract ongewijzigd → geen app-wijziging. DoD: `npx tsc --noEmit`
  groen in `backend/` én `admin/`; `build-v2.sh` "alles groen" (beide targets + Avatar2-tests +
  AvatarKit/AvatarUI-suites). Port-only: backend- én admin-deploy nog niet gedaan — expliciet
  besluit Thierry; daarna referenties seeden in het CMS (→ 54.2-bakeoff).
- Result (deploy 2026-07-04, op verzoek Thierry): SQL-migratie
  [017](../backend/sql/017_payload_effects_style_references.sql) door Thierry toegepast
  (Supabase SQL-editor; DDL 1:1 uit offline `payload migrate:create`-snapshot). Backend
  (avatars-api) én admin (avatar-admin) naar prod via Vercel CLI — beide vanaf repo-root
  (rootDirectory-setting; admin vergde een tijdelijke `.vercelignore`-swap, direct teruggezet).
  Keten geverifieerd: admin 307→/mfa, `/v1/effects` 200 met gevulde lijst (= join op de nieuwe
  tabel werkt), `/v1/banner-presets` 200. Bijvangst gefixt (5c38834): de nieuwe Payload-build
  hangt `?prefix=media` aan media-URLs waardoor de geankerde `thumbnailVariant`-regex (E52.1)
  elke thumbnail ongetransformeerd doorliet — query wordt nu genegeerd; render-variant
  prod-geverifieerd. Klaar voor gebruik: referenties per effect uploaden in het CMS.

Scope:
- `admin/src/collections/Effects.ts`: array-veld `styleReferences` (1–4 rijen, elk een
  upload→media), met admin-beschrijving over wat goede referenties zijn (doelstijl-output,
  liefst zónder prominent herkenbaar ander gezicht — identity-bleed-risico).
- `backend/lib/payload.ts`: `PayloadEffect.styleReferenceUrls: string[]` (vervangt het dooie
  enkelvoudige `styleReferenceUrl`); `normalizeEffect()` leest de array.
- `backend/api/v1/stylize.ts`: referenties parallel ophalen (cap 3, soft-fail per stuk), via de
  Supabase image-transformatie (`thumbnailVariant`, ~1024px) zodat grote CMS-uploads de call niet
  opblazen; in-process data-URL-cache (zelfde TTL-patroon als de effects-fetch). Zodra er
  referenties zijn: rolclausule aan de prompt toevoegen ("first image is the person; every other
  image is a style example only — match its style, do NOT copy any person/face/composition").
- `backend/lib/replicate.ts`: `stylizeEdit` accepteert `styleReferenceDataUrls: string[]`;
  de vier model-adapters (nano-banana, seedream, flux-2, gpt-image) appenden de hele lijst.
- DoD: `npx tsc --noEmit` groen in `backend/` én `admin/`, beide targets bouwen + package-tests
  groen (Swift ongewijzigd — contract `/v1/effects` verandert niet), Result-regel. Port-only:
  deploy van backend + admin is een expliciet besluit van Thierry ná merge.

## 54.2 — Bakeoff: stijltrouw & identiteitsbehoud met referenties
- status: done (eerste pas, nano-banana; multi-model-matrix = optionele vervolgstap)
- owner: AI (2026-07-12)
- team: AI
- blockedBy: — (54.1 done; referenties geseed 2026-07-12 — zie hieronder)

**Result (bakeoff 2026-07-12, nano-banana = productie-default; beeldmateriaal in
`~/Documents/Claude/Projects/Aaavatar/e54-bakeoff/`):** 4 effecten × {zonder, mét
referenties} × 2 E09-portretten (p1/p3) + 2 clausule-v2-armen, callshape 1-op-1 de
backend (`stylizeInputFor` + `STYLE_REFERENCE_CLAUSE`). **Verdict: referenties NIET
default aanzetten** —
- ✅ Geen identity-bleed: gezichtsloze referenties werken zoals gehoopt (de E54.1-regel
  klopt); de persoon blijft altijd de persoon.
- ❌ Maar fotografische object-referenties (clay/wood/3d = productfoto's van figurines)
  ankeren het model op het VERKEERDE: het kopieert achtergrondkleur, sokkel en
  compositie van de referentie en laat de persoon (grotendeels) fotografisch —
  stijltrouw ZAKT t.o.v. prompt-only (wood-p1-refs: foto-buste op houten sokkel;
  clay-p1-refs: nauwelijks transformatie). Oorzaak: het "medium" van de referentie
  (studiofoto) wordt als doelstijl gelezen, niet het materiaal.
- ✅ Scribble (referentie is zélf een tekening) = neutraal tot licht positief →
  medium-match is de bepalende variabele, niet het onderwerp.
- ❌ Clausule-tuning v2 ("alleen materiaal/textuur overnemen, compositie/achtergrond
  negeren, transformeer volledig") maakte het erger: bijna-passthrough van de foto.
- Bijvangst: nano-banana leverde ook één prompt-only-passthrough (clay-p3-noref, foto
  vrijwel onbewerkt terug) — bestaand kwaliteitsrisico los van referenties.
**Gevolg-actie (direct uitgevoerd):** de geseedde koppel-rijen zijn weer LOSGEHAALD
(`effects_style_references` leeg; media 11–18 + storage-bestanden blijven staan) —
anders had elke prod-stylize per direct de slechtere refs-arm gekregen (54.1-wiring
appendt automatisch). Herkoppelen = `seed_refs.py` opnieuw draaien.
**Aanbeveling:** default-flip afblazen; 54.3 (stijl-distillatie naar TEKST) is de
kansrijke route voor materiaal-effecten — dat omzeilt het medium-anker; referenties
evt. alleen voor tekening-achtige effecten heroverwegen, of referenties maken die
zelf in het doelmedium gerenderd zijn i.p.v. er een foto van te zijn.

**Seeding (2026-07-12, autonoom op verzoek Thierry):** per effect 2 stijlreferenties
gegenereerd met `google/nano-banana` (gezichtsloos conform de identity-bleed-regel:
clay=vos+zonnebloem, wood=vogel+beer, 3d=kat+robot, scribble=fiets+koffie), visueel
gereviewd, en in het CMS gezet — storage-upload naar `announcement-media/media/e54-*.png`
+ `payload.media`-rijen (id 11–18) + `payload.effects_style_references`-rijen via de
Supabase Management-API (de Payload-REST-key is Vercel-sensitive en dus niet leesbaar;
de DB-route is 1-op-1 wat Payload's drizzle-adapter verwacht, DDL uit sql/017).
Publieke URL geverifieerd (200, image/png). NB: verwissel/vervang kan gewoon via de
admin-UI; de rijen zijn additief.

E09.1/E41-patroon: per stylize-model (nano-banana, flux-2-pro, gpt-image-1.5) met/zonder
referenties op een vast testportret, beoordeeld op (a) stijltrouw aan de voorbeelden en
(b) identiteitsbehoud (identity-bleed uit referenties met gezichten expliciet testen).
Uitkomst: aanbevolen referentie-aantal + evt. clausule-tuning; besluit of de default-flip
(referenties aan voor alle users) doorgaat.

## 54.3 — Stijl-distillatie uit referenties (optioneel)
- status: backlog
- team: INFRA+AI
- blockedBy: 54.2

Bij opslaan in het CMS (Payload-hook of knop) destilleert een vision-model eenmalig een
gedetailleerde stijlbeschrijving uit de referenties en zet die in een server-only veld dat aan de
prompt wordt toegevoegd. Tekst + beeld versterken elkaar; helpt vooral bij modellen waar extra
input-images identiteitsbehoud verzwakken. Alleen bouwen als 54.2 laat zien dat referenties
alléén niet genoeg zijn.

## 54.4 — Model-override per effect in het CMS (optioneel)
- status: backlog
- team: INFRA

Optioneel select-veld `model` op de Effects-collectie (whitelist uit `MODEL_REGISTRY.stylize`),
zodat een stijl die beter rendert op bv. flux-2-pro dat per effect kan afdwingen zonder deploy.
Precedentie onder de bestaande dev-`model_override`, boven de gebruikers-`generation_model`
— besluit over die volgorde bij de story zelf.
