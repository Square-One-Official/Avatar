# E52 — CMS-media-performance (thumbnails)

Team: **INFRA + FEAT**

Aanleiding (Thierry, 2026-07-02): thumbnails van CMS-content (backgrounds,
hair/clothes/face-presets, effects-stijlreferenties) laden in de app "een paar
seconden". Media wordt sinds `837498f` als **origineel** via directe Supabase
Storage-URL's geserveerd — geen afgeleide thumbnail-maten, geen expliciete
cache-headers, geen client-side cache/prefetch. Panels decoderen dus full-size
bronnen voor grid-cellen van ~100–200 pt.

## 52.1 — Thumbnail-varianten server-side + client-cache
- status: done
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

**Result (2026-07-02):** Supabase image-transformatie bleek op het prod-project
beschikbaar (`/render/image/public/…?width=…&quality=…` → 200, CDN-HIT op de
2e hit) — geen re-upload/Payload-`imageSizes` nodig. Server: `thumbnailVariant()`
in `backend/lib/payload.ts` herschrijft de bestaande public-object-URL's naar
render-varianten (backgrounds 160 px, effects/presets 320 px, banner-presets
480 px); `/v1/backgrounds|effects|banner-presets|hair-|clothes-|face-presets`
sturen nu `thumbnail_url` (presets: nieuw veld, depth=1) + gedeelde
`Cache-Control: public, max-age=60, s-maxage=300, stale-while-revalidate=600`.
Client: nieuwe `ThumbnailCache` (AvatarKit) — memory (NSCache) + disk
(`Caches/CMSThumbnails`, SHA-256-keyed) + in-flight-dedupe + CGImageSource-
downsampled decode (max 640 px), latency per load + prefetch-batch gelogd via
os.Logger/OSSignposter (`thumbnail.load`/`thumbnail.prefetch`). Panels
(Background/Effects/FaceActions, Home/BannersGallery via `RemoteThumbnail`)
prefetchen bij open, tonen de variant en halen het origineel pas bij toepassen;
fallback `thumbnail_url ?? image_url` blijft client-side intact. Meting (4
prod-effect-thumbs, parallel): origineel 33–163 KB / 0,19–0,38 s p.st. →
variant 18–81 KB, koud (transform-miss) 0,39–0,56 s, CDN-warm 0,14–0,23 s;
her-open memory/disk-instant. Tests: `ThumbnailCacheTests` (miss→hit, disk-hit
over instanties, soft-fail, downsample-cap) + decode-fixtures voor
`thumbnail_url` op hair-/face-presets en backgrounds — AvatarKit 100/100,
AvatarUI 37/37, Avatar2 123/123 (1 skip), beide app-targets bouwen,
`tsc --noEmit` schoon. Backend-wijzigingen liften mee op de volgende deploy
(geen deploy gedaan).

## 52.2 — Prefetch/warming + metingen (backlog)
- status: backlog (effects-deel done via E55.6, 2026-08-02)
- team: FEAT
- blockedBy: 52.1

Warming van de meest gebruikte categorieën bij app-start (achter een setting),
signposts/metingen rond thumbnail-latency zodat regressies zichtbaar worden.

NB (E55.6): voor **effects** is dit gebouwd — launch-prewarm
(`EffectsModel.prewarm` in Avatar2App) + disk-persistentie van de lijst-JSON
(`EffectsListCache`) + LRU-byte-cap op ThumbnailCache. Resterende scope hier:
backgrounds/hair/clothes/face/banner-presets + de regressie-metingen.
