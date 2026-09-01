-- E56 — race-safe credit spend for paid generation endpoints.
--
-- `current_credits()` followed by a ledger insert is a check-then-act race:
-- two requests can both observe the same balance and overspend it. Serialise
-- spends per user inside one transaction, re-check the active-period balance,
-- and append the negative ledger row only when sufficient credit remains.

create or replace function public.try_spend_credits(
  p_user uuid,
  p_amount int,
  p_reason text,
  p_ref text default null
)
returns int
language plpgsql
as $$
declare
  v_balance int;
begin
  if p_amount <= 0 then
    raise exception 'p_amount must be positive';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user::text, 0)
  );
  v_balance := public.current_credits(p_user);
  if v_balance < p_amount then
    return null;
  end if;

  insert into public.credit_ledger (user_id, delta, reason, ref)
  values (p_user, -p_amount, p_reason, p_ref);

  return v_balance - p_amount;
end;
$$;

alter function public.try_spend_credits(uuid, int, text, text)
  set search_path = '';

-- A request reference can be spent and refunded at most once. The pair of
-- partial indexes keeps retries idempotent without constraining unrelated
-- historical ledger rows whose refs have different semantics.
create unique index if not exists credit_ledger_fill_body_spend_ref_unique
  on public.credit_ledger (reason, ref)
  where reason = 'fill_body' and ref is not null;

create unique index if not exists credit_ledger_fill_body_refund_ref_unique
  on public.credit_ledger (reason, ref)
  where reason = 'fill_body_refund' and ref is not null;

create or replace function public.refund_credit_spend(
  p_user uuid,
  p_amount int,
  p_reason text,
  p_ref text
)
returns boolean
language plpgsql
as $$
begin
  if p_amount <= 0 or p_ref is null or p_ref = '' then
    raise exception 'valid amount and reference required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_user::text, 0)
  );
  if not exists (
    select 1
    from public.credit_ledger
    where user_id = p_user
      and reason = p_reason
      and ref = p_ref
      and delta = -p_amount
  ) then
    return false;
  end if;
  if exists (
    select 1
    from public.credit_ledger
    where user_id = p_user
      and reason = p_reason || '_refund'
      and ref = p_ref
  ) then
    return true;
  end if;

  insert into public.credit_ledger (user_id, delta, reason, ref)
  values (p_user, p_amount, p_reason || '_refund', p_ref);
  return true;
end;
$$;

alter function public.refund_credit_spend(uuid, int, text, text)
  set search_path = '';
