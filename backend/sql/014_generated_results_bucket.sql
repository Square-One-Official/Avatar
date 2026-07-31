-- Avatars API — generated background RESULT bucket.
-- The OUTPUT counterpart to 006_cutout_uploads_bucket.sql. Vercel's 4.5 MB
-- function body cap applies to RESPONSES too: a full-frame, opaque generated
-- background returned inline as base64 can exceed it and truncate silently,
-- leaving the user charged with no image. The fix mirrors the input path —
-- /v1/generate-background uploads the (WebP-compressed) result here and hands
-- the client a short-lived signed read URL it downloads straight from Storage,
-- so the bytes never traverse Vercel on the way back either.
--
-- Bucket is private; access is gated entirely by signed URLs issued by the
-- service role from inside Vercel functions. We deliberately do NOT add public
-- RLS policies — without policies, RLS denies everything to non-service roles,
-- which is exactly what we want.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'generated-results',
  'generated-results',
  false,
  10 * 1024 * 1024,             -- 10 MB hard cap; WebP results are well under 1 MB
  array['image/webp', 'image/png', 'image/jpeg']
)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  public = excluded.public;
