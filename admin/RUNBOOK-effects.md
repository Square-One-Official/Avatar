# Runbook — Effects-stijlen beheren (CMS)

Voor het toevoegen/bijwerken van Effects-stijlen in de Payload-admin
(admin.aaavatar.nl → collectie **Effects**). De app leest ze via
`GET api.aaavatar.nl/v1/effects` (±5 min CDN-cache); `prompt` en
`styleReferences` blijven server-only.

## Een stijl toevoegen via de admin-UI

1. **Media eerst**: upload de thumbnail en 1–4 referentiebeelden in **Media**.
   - *Thumbnail*: staand (~3:4), PNG/JPG, lange zijde ≥ 640 px (de kaart toont
     een 320 px-CDN-variant; groter uploaden mag, wordt automatisch verkleind
     geserveerd). Toon het effect op een **fictief persoon** — nooit een echte
     gebruiker of beroemdheid.
   - *Referenties* (E54): beelden die de DOELSTIJL tonen, liefst **in het
     doelmedium zelf** (een tekening voor een tekenstijl, een render voor een
     3D-stijl — géén studiofoto van een object; dat ankert het model op de
     foto-look, zie de E54.2-bakeoff). **Geen herkenbare gezichten** (identity-
     bleed) en **geen logo's** (logo-bleed). Max 4 in het CMS; de backend
     stuurt er maximaal 3 mee.
2. **Effects → Create new**:
   - `key`: stabiele slug (a-z, streepjes). **Nooit hernoemen** — de key is ook
     de on-device cachekey; hernoemen orphant caches bij gebruikers.
   - `label`: kaartnaam in de app.
   - `prompt`: de stijlinstructie. **Eindig altijd op de identity-clausule**:
     *"Keep the person's facial features, expression, hairstyle and clothing
     clearly recognizable so the person remains identifiable."*
   - `thumbnail` + `styleReferences`: koppel de media van stap 1.
   - `order`: lager = eerder in de rail. Actieve reeks: zie bestaande stijlen.
   - `active`: aanvinken zodra de stijl live mag; uitvinken i.p.v. verwijderen
     (verwijderen breekt niets bij gebruikers — selectie is key-gebaseerd —
     maar uitzetten is omkeerbaar).
3. **Verifiëren** (na ±5 min cache):
   ```sh
   curl -s https://api.aaavatar.nl/v1/effects | python3 -m json.tool
   ```
   - De nieuwe stijl staat erin, op de juiste plek.
   - `thumbnail_url` begint met `https://…storage.supabase.co/storage/v1/render/image/public/…`.
     Zie je een `admin.aaavatar.nl/api/media/file/…`-URL → de admin-deploy mist
     de `generateFileURL`-fix (837498f/E55.5); de app kan die URL **niet**
     laden (MFA-401) en de CDN-verkleining vervalt. Eerst de admin-deploy
     fixen, dan de media opnieuw uploaden.
4. **In de app**: Effects-paneel openen → nieuwe kaart met thumbnail → stijl
   genereren op een testportret. Let op stijltrouw én dat de persoon herkenbaar
   blijft.

## Bulk: de curatiemap importeren

Voor de zes E55-stijlen (en toekomstige batches) bestaat
`backend/scripts/import-effects.mjs` — leest
`~/Documents/Aaavatar_ChatGPT Images 2.0 Edit_…/Effects/<Naam>/{References/,Thumbnail/}`
plus `_aaavatar-seed/effects-seed.json` (prompts/keys/orders), normaliseert
(refs ≤1024 px, thumbs ≤800 px, GIF → eerste frame) en upsert per key
(idempotent). Standaard dry-run met gap-rapport; schrijven = `--apply`.

```sh
bash backend/scripts/run-import-effects.sh          # env pull + dry-run + bevestiging
node backend/scripts/import-effects.mjs             # alleen het gap-rapport (geen env nodig)
node backend/scripts/import-effects.mjs --apply --only balloon
node backend/scripts/import-effects.mjs --deactivate clay,wood,3d,scribble --apply
```

De echte run doet eerst een **URL-probe** (mini-upload → check directe
Supabase-URL → delete) en weigert te seeden op een proxy-URL-admin.

## Modelkeuze & referenties

Sinds E55.2 is **gpt-image-1.5** de default-engine (beste stijlmatch met
referenties); rollback = env `STYLIZE_DEFAULT_MODEL=nano-banana` op avatars-api
+ redeploy. Referenties wegen op gpt-image anders dan op nano-banana — bij een
nieuwe stijl zonder bakeoff: eerst prompt-only testen, dan refs erbij en
vergelijken (E55.7-werkwijze).
