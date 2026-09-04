-- E14.12 — top-up credits survive the monthly renewal (two-bucket balance).
--
-- Problem (audit 2026-09-04): `current_credits()` (001, rewritten in 009)
-- summed every ledger row with `created_at >= subscriptions.current_period_start`
-- of the latest active subscription. That window drops *all* older rows at
-- renewal — including `topup_pack` grants bought earlier — while the client
-- promises the opposite ("Credits never expire and stack with your monthly
-- credits", SettingsBillingPage / BillingCopy / `CreditPack` doc comment).
-- Side effects of the old window:
--   * a top-up bought on the 28th was gone on the 1st;
--   * a lapsed subscriber counted their whole history (every unspent monthly
--     grant ever), so leftovers inflated instead of expiring;
--   * balance depended on the `subscriptions` mirror being fresh (the 009
--     multi-row edge case, past_due/dunning gaps, API-version drift).
--
-- Decision (option a, see plan/E14-monetization.md §14.12): the MONTHLY grant
-- refills — unspent monthly credits drop when the next period is granted —
-- and TOP-UP credits never expire. Spends draw from the monthly bucket first
-- (use the expiring credits first), then from the top-up bucket.
--
-- Implementation: the balance is a fold over the user's ledger in insertion
-- order with two buckets, `monthly` (M) and `topup` (T):
--   * reason = 'topup_pack'                       → T += delta
--   * reason = 'period_renewal', ref without ':N' → M  = delta   (new billing
--     period: monthly invoice, or the ':0' up-front tranche of a yearly sub)
--   * any other positive row                      → M += delta   (yearly cron
--     tranches ':1'..':11', comped_pro top-ups, *_refund, initial_grant, manual
--     comps) — a yearly sub therefore still accumulates within its year, as
--     it does today, and resets at the yearly renewal
--   * negative row (spend)                        → M first, then T; T is
--     floored at 0 so pre-migration histories that over-spent under the old
--     window (lapsed users) are forgiven rather than carried as debt
--   balance = M + T.
-- The fold no longer reads `subscriptions` at all: renewals are detected
-- from the ledger itself (the webhook writes the period_renewal row on the
-- same invoice.paid that moves the period), so audit MEDIUM #18 (009) and the
-- dunning gap disappear as a class.
--
-- Semantics kept unchanged: `try_spend_credits` / `refund_credit_spend` (020)
-- and `ensureCompedCredits` (backend/lib/supabase.ts) only call
-- `current_credits()`, so no TypeScript changes are required.
--
-- Who changes balance at apply time: monthly subscribers with older top-ups
-- go UP (their top-ups come back); lapsed subscribers with several unspent
-- historical grants go DOWN to "last period's leftover + top-ups". Run the
-- pre-flight in section 3 between sections 1 and 2 to see the exact list.
--
-- Run order: depends on 001_init.sql, 002_v1_extensions.sql (topup_pack) and
-- 020_atomic_credit_spend.sql (callers). Apply in the Supabase SQL editor in
-- three steps: section 1, then the pre-flight (section 3), then section 2.

-- ---------------------------------------------------------------------------
-- 1. Pure fold + per-user buckets (additive; does not touch current_credits)
-- ---------------------------------------------------------------------------

create or replace function public.credit_bucket_fold(
  p_delta  int[],
  p_reason text[],
  p_ref    text[]
)
returns table (monthly int, topup int)
language plpgsql
immutable
as $$
declare
  v_m      int := 0;
  v_t      int := 0;
  v_i      int;
  v_delta  int;
  v_reason text;
  v_ref    text;
  v_spend  int;
  v_from_m int;
begin
  for v_i in 1 .. coalesce(array_length(p_delta, 1), 0) loop
    v_delta  := p_delta[v_i];
    v_reason := p_reason[v_i];
    v_ref    := p_ref[v_i];

    if v_reason = 'topup_pack' then
      -- Never expires. A negative topup row (future chargeback reversal)
      -- is honoured as debt, not floored.
      v_t := v_t + v_delta;
    elsif v_delta >= 0 then
      if v_reason = 'period_renewal'
         and (v_ref is null or v_ref !~ ':[1-9][0-9]*$') then
        -- New billing period: the monthly bucket refills, it does not stack.
        v_m := v_delta;
      else
        v_m := v_m + v_delta;
      end if;
    else
      v_spend  := -v_delta;
      v_from_m := least(v_m, v_spend);
      v_m      := v_m - v_from_m;
      v_t      := greatest(0, v_t - (v_spend - v_from_m));
    end if;
  end loop;

  monthly := v_m;
  topup   := v_t;
  return next;
end;
$$;

alter function public.credit_bucket_fold(int[], text[], text[])
  set search_path = '';

create or replace function public.credit_buckets(p_user uuid)
returns table (monthly int, topup int)
language sql
stable
as $$
  select f.monthly, f.topup
  from (
    select
      coalesce(array_agg(l.delta  order by l.created_at, l.id), '{}'::int[])  as deltas,
      coalesce(array_agg(l.reason order by l.created_at, l.id), '{}'::text[]) as reasons,
      coalesce(array_agg(l.ref    order by l.created_at, l.id), '{}'::text[]) as refs
    from public.credit_ledger l
    where l.user_id = p_user
  ) a
  cross join lateral public.credit_bucket_fold(a.deltas, a.reasons, a.refs) f;
$$;

alter function public.credit_buckets(uuid) set search_path = '';

-- Self-check: the migration aborts here if the fold does not implement the
-- semantics above. Pure arrays, no table writes — safe on production.
do $$
declare
  r record;
begin
  -- (1) empty ledger → 0/0
  select * into r from public.credit_bucket_fold('{}', '{}', '{}');
  if r.monthly <> 0 or r.topup <> 0 then
    raise exception 'fold: empty ledger gave %/%', r.monthly, r.topup;
  end if;

  -- (2) monthly renewal refills instead of stacking: 200 grant, spend 50,
  --     next invoice → 200, not 350.
  select * into r from public.credit_bucket_fold(
    '{200,-50,200}', '{period_renewal,stylize,period_renewal}', '{in_1,pred_a,in_2}');
  if r.monthly <> 200 or r.topup <> 0 then
    raise exception 'fold: monthly refill gave %/%', r.monthly, r.topup;
  end if;

  -- (3) THE BUG: top-up bought before the renewal survives it.
  --     200 grant, top-up 50, spend 30 (from monthly), renewal → 200 + 50.
  select * into r from public.credit_bucket_fold(
    '{200,50,-30,200}', '{period_renewal,topup_pack,stylize,period_renewal}',
    '{in_1,in_topup_1,pred_a,in_2}');
  if r.monthly <> 200 or r.topup <> 50 then
    raise exception 'fold: top-up across renewal gave %/%', r.monthly, r.topup;
  end if;

  -- (4) spends drain the monthly bucket first, then the top-up bucket.
  --     200 grant, top-up 50, spend 230 → monthly 0, top-up 20; renewal → 200/20.
  select * into r from public.credit_bucket_fold(
    '{200,50,-230,200}', '{period_renewal,topup_pack,stylize,period_renewal}',
    '{in_1,in_topup_1,pred_a,in_2}');
  if r.monthly <> 200 or r.topup <> 20 then
    raise exception 'fold: monthly-first drain gave %/%', r.monthly, r.topup;
  end if;

  -- (5) yearly: ':0' resets, ':1'..':11' accumulate within the year, the next
  --     year's ':0' resets again.
  select * into r from public.credit_bucket_fold(
    '{200,200,-100,200,200}',
    '{period_renewal,period_renewal,stylize,period_renewal,period_renewal}',
    '{in_y1:0,in_y1:1,pred_a,in_y1:11,in_y2:0}');
  if r.monthly <> 200 or r.topup <> 0 then
    raise exception 'fold: yearly tranches gave %/%', r.monthly, r.topup;
  end if;
  select * into r from public.credit_bucket_fold(
    '{200,200,-100,200}',
    '{period_renewal,period_renewal,stylize,period_renewal}',
    '{in_y1:0,in_y1:1,pred_a,in_y1:2}');
  if r.monthly <> 500 or r.topup <> 0 then
    raise exception 'fold: yearly accumulation gave %/%', r.monthly, r.topup;
  end if;

  -- (6) comped Pro (top-to-allowance, no Stripe period) and refunds add to
  --     the monthly bucket without resetting it.
  select * into r from public.credit_bucket_fold(
    '{200,-40,40,160}', '{comped_pro,fill_body,fill_body_refund,comped_pro}',
    '{comped:u:2026-08,req_1,req_1,comped:u:2026-09}');
  if r.monthly <> 360 or r.topup <> 0 then
    raise exception 'fold: comped/refund gave %/%', r.monthly, r.topup;
  end if;

  -- (7) lapsed user keeps last period's leftover + top-ups; a legacy
  --     over-spend (allowed by the old whole-history window) is forgiven,
  --     not carried as debt into the next subscription.
  select * into r from public.credit_bucket_fold(
    '{200,-100,200,-300,200}',
    '{period_renewal,stylize,period_renewal,stylize,period_renewal}',
    '{in_1,pred_a,in_2,pred_b,in_3}');
  if r.monthly <> 200 or r.topup <> 0 then
    raise exception 'fold: legacy over-spend gave %/%', r.monthly, r.topup;
  end if;

  -- (8) top-ups only (no subscription ever): plain sum.
  select * into r from public.credit_bucket_fold(
    '{50,-20,200}', '{topup_pack,stylize,topup_pack}', '{in_t1,pred_a,in_t2}');
  if r.monthly <> 0 or r.topup <> 230 then
    raise exception 'fold: topup-only gave %/%', r.monthly, r.topup;
  end if;

  -- (9) null refs (legacy manual rows) are treated as a period boundary only
  --     for period_renewal; other reasons just add.
  select * into r from public.credit_bucket_fold(
    '{200,25,200}', '{period_renewal,initial_grant,period_renewal}',
    '{NULL,NULL,NULL}');
  if r.monthly <> 200 or r.topup <> 0 then
    raise exception 'fold: null refs gave %/%', r.monthly, r.topup;
  end if;

  raise notice '022 credit_bucket_fold self-check passed';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Switch the balance over. `try_spend_credits` / `refund_credit_spend`
--    (020) and every backend caller go through this function, so this is the
--    whole cut-over.
-- ---------------------------------------------------------------------------

create or replace function public.current_credits(p_user uuid)
returns int
language sql
stable
as $$
  select coalesce((b.monthly + b.topup)::int, 0)
  from public.credit_buckets(p_user) b;
$$;

-- Re-pin the search_path — `create or replace function` resets the
-- per-function settings (007_lint_security_fixes.sql).
alter function public.current_credits(uuid) set search_path = '';

-- ---------------------------------------------------------------------------
-- 3. Pre-flight (run BETWEEN section 1 and section 2, read-only): every user
--    whose balance changes at cut-over, old window vs. new buckets.
-- ---------------------------------------------------------------------------
-- select u.id,
--        public.current_credits(u.id)                       as old_balance,
--        b.monthly + b.topup                                as new_balance,
--        b.monthly, b.topup,
--        (select s.status from public.subscriptions s
--          where s.user_id = u.id
--          order by s.current_period_start desc nulls last limit 1) as sub_status
-- from public.users u
-- cross join lateral public.credit_buckets(u.id) b
-- where public.current_credits(u.id) <> b.monthly + b.topup
-- order by (b.monthly + b.topup) - public.current_credits(u.id);
