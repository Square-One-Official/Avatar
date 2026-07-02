# E52 — CMS-media-performance (thumbnails)

Team: **INFRA + FEAT**

Aanleiding (Thierry, 2026-07-02): thumbnails van CMS-content (backgrounds,
hair/clothes/face-presets, effects-stijlreferenties) laden in de app "een paar
seconden". Media wordt sinds `837498f` als **origineel** via directe Supabase
Storage-URL's geserveerd — geen afgeleide thumbnail-maten, geen expliciete
cache-headers, geen client-side cache/prefetch. Panels decoderen dus full-size
bronnen voor grid-cellen van ~100–200 pt.

## 52.1 — Thumbnail-varianten server-side + client-cache
- status: ready
- team: INFRA + FEAT
- blockedBy: —

**Wat:** eerste-load van CMS-grids voelt traag (seconden), her-open opnieuw.
**Voorstel (twee kanten):**
1. **Server/CMS:** afgeleide thumb-maat per media-item — via Supabase
   image-transformatie (`/render/image/...?width=…&quality=…`) op de bestaande
   publieke URL's, óf Payload `imageSizes` bij upload. Endpoints
   (`/v1/backgrounds`, `/v1/*-presets`, `/v1/effects`) geven naast `url` een
   `thumbnailUrl`. Cache-headers op media-responses (immutable, lange max-age —
   URL's zijn content-addressed per upload).
2. **Client:** panels laden `thumbnailUrl` i.p.v. origineel; downsampled decode
   (CGImageSource thumbnail-API) als het tóch een groot origineel is; disk-cache
   (URLCache of eigen store) zodat her-opens instant zijn; prefetch bij
   panel-open. Origineel pas ophalen bij daadwerkelijk toepassen.
**DoD:** koud panel-open toont thumbs < ~500 ms op normale verbinding (meetbaar
gelogd), her-open instant uit cache; fallback naar `url` als `thumbnailUrl`
ontbreekt (oude CMS-items); beide targets bouwen; tests groen; Result-regel.

## 52.2 — Prefetch/warming + metingen (backlog)
- status: backlog
- team: FEAT
- blockedBy: 52.1

Warming van de meest gebruikte categorieën bij app-start (achter een setting),
signposts/metingen rond thumbnail-latency zodat regressies zichtbaar worden.
