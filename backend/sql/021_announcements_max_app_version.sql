-- E13/2.0-launch (2026-09-04): Announcements krijgt `maxAppVersion` naast
-- `minAppVersion`, zodat een "Aaavatar 2 is uit"-bericht alléén 1.x-installs
-- bereikt (v1 stuurt geen X-App-Version → passeert de max-gate; 2.0 stuurt
-- 2.0.0 → valt eruit). Backend-filter: api/v1/announcements/pending.ts.
--
-- Payload-schema is handmatig (push:false). DDL 1:1 uit de offline
-- `payload migrate:create`-snapshot van 2026-09-04 (snapshot niet gecommit),
-- idempotent. Toepassen in de Supabase SQL-editor VÓÓR de admin-deploy
-- (= vóór de main-push): een ontbrekende kolom maakt élke announcement-
-- detailpagina zwart en laat /v1/announcements/pending soft-failen op null.

ALTER TABLE "payload"."announcements"
  ADD COLUMN IF NOT EXISTS "max_app_version" varchar;

-- Verificatie:
--   select column_name, data_type from information_schema.columns
--    where table_schema = 'payload' and table_name = 'announcements'
--      and column_name in ('min_app_version', 'max_app_version');
