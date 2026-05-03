-- Avatars API — pre-auth checkout support.
-- A `device_grants` row marks "this device paid for Pro before its owner
-- signed in to a Supabase account." The Stripe webhook upserts the row when
-- it processes a checkout.session.completed for a session that has a
-- client_reference_id (= device fingerprint) but no supabase_user_id (= the
-- new anonymous flow). The /v1/account endpoint reads this table when a
-- request arrives without an Authorization header so the macOS app can
-- recognise its own device as Pro without forcing sign-in.
--
-- The user_id column references the Supabase auth user the webhook
-- created/found by email — that account owns the subscription and credits.
-- When the user later signs in with that email (e.g. via the magic link sent
-- after checkout) entitlement becomes account-scoped and the device row is
-- redundant but harmless.

create table if not exists public.device_grants (
  device_fingerprint text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null check (source in ('stripe_checkout')),
  granted_at timestamptz not null default now()
);

create index if not exists device_grants_user_id_idx
  on public.device_grants (user_id);
