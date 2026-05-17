-- Audit MEDIUM #18: `current_credits()` over-counts (or under-counts)
-- when a user has more than one row in `subscriptions` for any reason —
-- the LEFT JOIN multiplies every ledger entry by the matching
-- subscription count, and `l.created_at >= s.current_period_start`
-- picks whichever sub-row Postgres happened to scan first.
--
-- Real-world triggers we've seen:
--   * Stripe re-creates a subscription on dunning recovery → two rows,
--     one cancelled and one active, both still in the table.
--   * Webhook retry order races a customer.subscription.updated against
--     a customer.subscription.created → both upsert hits land.
--   * Dev / test imports from a Stripe Sandbox seeding loop.
--
-- Fix: pre-select the *latest active* subscription via a CTE, then
-- aggregate ledger entries with respect to that single window. Behaviour
-- for users without any subscription (free tier, topup-only) is
-- unchanged: the CTE returns an empty row, the `is null` branch
-- short-circuits the window check, and every ledger entry contributes.
--
-- Run order: depends on 001_init.sql + 007_lint_security_fixes.sql.

create or replace function public.current_credits(p_user uuid)
returns int
language sql
stable
as $$
  with latest_period as (
    select s.current_period_start
    from public.subscriptions s
    where s.user_id = p_user
      and s.status in ('active', 'trialing', 'past_due')
    order by s.current_period_start desc nulls last
    limit 1
  )
  select coalesce(sum(l.delta), 0)::int
  from public.credit_ledger l
  left join latest_period p on true
  where l.user_id = p_user
    and (p.current_period_start is null
         or l.created_at >= p.current_period_start);
$$;

-- Re-pin the search_path — `create or replace function` resets the
-- per-function settings, so the lockdown applied by
-- 007_lint_security_fixes.sql has to be reapplied here.
alter function public.current_credits(uuid) set search_path = '';
