-- Avatars API — feature-announcement system.
--
-- The CMS (Payload v3 at admin.aaavatar.nl) owns the announcement *content*
-- in its own `payload.*` schema. This migration lives in `public` and only
-- tracks per-user state — what the macOS app needs to ask "has this user
-- already seen announcement X?" — plus the Payload schema namespace so
-- Payload's first migration has somewhere to land.
--
-- Why not `@AppStorage`? Seen-state is a server concern. Reinstalling the
-- app or signing in on a second Mac must NOT re-show old pop-ups; that's
-- the whole point of having an account.

create schema if not exists payload;

-- 1. Per-user "I've seen this" log. Idempotent on (user_id, slug) so the
-- client can call /v1/announcements/seen multiple times without duplicating
-- rows — useful when the modal's dismiss handler fires once on tap and
-- again on `.onDisappear` due to SwiftUI sheet quirks.
create table if not exists public.announcement_seen (
  user_id  uuid not null references auth.users(id) on delete cascade,
  slug     text not null,
  seen_at  timestamptz not null default now(),
  action   text not null check (action in ('dismissed', 'cta_clicked')),
  primary key (user_id, slug)
);

-- 2. Slug index. The /pending endpoint joins on slug to filter out already-
-- seen announcements; this index keeps that join cheap as the table grows.
create index if not exists announcement_seen_slug_idx
  on public.announcement_seen (slug);

-- 3. RLS — service role bypasses, so the existing backend reads/writes
-- without policy churn. We still enable RLS so a future direct-from-client
-- access path doesn't accidentally expose other users' seen-state.
alter table public.announcement_seen enable row level security;
