-- Avatars API — Magic Cutout input bucket.
-- Vercel's serverless function body cap is 4.5 MB platform-wide. A 2048×2048
-- portrait PNG can easily exceed that once base64-wrapped, which made the iOS
-- client see a 413 from the edge and fall back with the "had a hiccup" toast.
-- The fix: clients upload PNGs directly to this private bucket via short-lived
-- signed PUT URLs, then call /v1/cutout with just the resulting object key.
-- The function turns that key into a signed read URL and hands it to Replicate
-- — bytes never traverse Vercel.
--
-- Bucket is private; access is gated entirely by signed URLs issued by the
-- service role from inside Vercel functions. We deliberately do NOT add public
-- RLS policies — without policies, RLS denies everything to non-service roles,
-- which is exactly what we want.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'cutout-uploads',
  'cutout-uploads',
  false,
  21 * 1024 * 1024,             -- 21 MB hard cap; client guards at 20 MB with 1 MB headroom
  array['image/png']
)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  public = excluded.public;
