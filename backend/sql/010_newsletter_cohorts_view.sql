-- Audit HIGH #12 finishes the work CRITICAL #1 started: drop the admin
-- app's dependency on `SUPABASE_SERVICE_ROLE_KEY` so an admin compromise
-- can no longer enumerate every account email via the GoTrue admin API.
--
-- The admin needs cohort emails (all / freeUsers / proUsers) for
-- newsletter sends. Instead of calling `supabase.auth.admin.listUsers()`,
-- the admin now reads a materialised view that the backend's service
-- role refreshes via a SECURITY DEFINER function — the admin's scoped
-- `payload_app` role gets SELECT on the view and EXECUTE on the
-- function, and never touches `auth.users` directly.
--
-- Run order: depends on 001_init.sql + 008_payload_scoped_role.sql.

-- 1. Materialised view: one row per confirmed-email user with a
--    pre-computed `tier`. EXISTS-subquery instead of LEFT JOIN so a user
--    with stale-but-active duplicate subscriptions (see 009) doesn't
--    appear twice.
create materialized view if not exists public.newsletter_cohorts as
select
  u.id as user_id,
  lower(u.email) as email,
  case
    when exists (
      select 1
      from public.subscriptions s
      where s.user_id = u.id
        and s.status in ('active', 'trialing')
    ) then 'pro'
    else 'free'
  end as tier
from auth.users u
where u.email_confirmed_at is not null
  and u.email is not null;

-- 2. Unique index so `REFRESH MATERIALIZED VIEW CONCURRENTLY` works —
--    without a unique index Postgres refuses the concurrent refresh and
--    we'd block readers during every cohort rebuild.
create unique index if not exists newsletter_cohorts_user_id_idx
  on public.newsletter_cohorts (user_id);

-- 3. Helpful secondary index for the admin's tier-filtered queries
--    (`where tier = 'pro'` / `'free'`).
create index if not exists newsletter_cohorts_tier_idx
  on public.newsletter_cohorts (tier);

-- 4. SECURITY DEFINER refresh function. Owned by the migration runner
--    (typically `postgres`), so it can REFRESH the view even though the
--    caller (`payload_app`) has no privileges on `auth.users` or
--    `public.subscriptions`. The CONCURRENTLY clause keeps the view
--    readable during refresh — important when the admin is mid-send.
create or replace function public.refresh_newsletter_cohorts()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  refresh materialized view concurrently public.newsletter_cohorts;
end;
$$;

-- 5. Grants for the scoped admin role.
grant select on public.newsletter_cohorts to payload_app;
grant execute on function public.refresh_newsletter_cohorts() to payload_app;

-- 6. Initial population. The CONCURRENTLY refresh used by the function
--    requires the view to already have rows, so seed it the first time
--    here with a plain refresh.
refresh materialized view public.newsletter_cohorts;
