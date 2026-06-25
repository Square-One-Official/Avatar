-- Avatars API — user-created custom Effects (E34).
-- A Pro user creates their own Effect from a reference image + a short
-- description. The reference image both drives the generation (passed to the
-- model as a style reference) and is the card thumbnail. Effects sync per
-- account, so they live server-side (not local-only).
--
-- The description is the generation `prompt`; like the built-in CMS effects it
-- stays server-side (only /v1/stylize reads it). The reference image lives in
-- the public `custom-effects` Storage bucket so the client can render the
-- thumbnail by URL, and /v1/stylize re-reads the same object server-side.

-- 1. Per-user custom effect definitions.
create table if not exists public.custom_effects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  label text not null,
  prompt text not null default '',                 -- the user's description (style refinement)
  reference_path text not null,                    -- object path in the custom-effects bucket
  created_at timestamptz not null default now()
);

create index if not exists custom_effects_owner_created_idx
  on public.custom_effects (owner_id, created_at desc);

-- RLS on. All access goes through Vercel functions with the service role
-- (which bypasses RLS) and filters by owner_id explicitly; enabling RLS with
-- no permissive policy denies every other (anon/authenticated) path by
-- default — defense in depth against a leaked anon key.
alter table public.custom_effects enable row level security;

-- 2. Public bucket for the reference images / thumbnails. Public so the macOS
-- client can load the thumbnail straight from the object URL (like the CMS
-- background/effect thumbnails). Writes only ever happen from the service role
-- inside /v1/custom-effects, so no public write policy is added.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'custom-effects',
  'custom-effects',
  true,
  6 * 1024 * 1024,              -- 6 MB; client downscales references to ≤1024px PNG
  array['image/png']
)
on conflict (id) do update set
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types,
  public = excluded.public;
