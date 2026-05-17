-- Audit MEDIUM #19: signed-out import burns advanced only the
-- per-device counter (`device_imports.free_imports_used`); the
-- per-account counter (`users.free_imports_used`) didn't move because
-- there was no user row to attribute them to. A user could exploit this
-- by burning N imports signed-out on device A, then signing in on
-- device B (fresh fingerprint = device counter 0) to get a fresh
-- allowance — the global 6-import cap was effectively per-device for
-- anyone willing to swap devices after signing out.
--
-- Fix: on the first `try_consume_free_import` call for any new
-- (device, user) pair, lift the account counter to `max(account, device)`
-- so signed-out usage on this device counts against the account-wide
-- cap from that point forward. The merge is one-shot per pair, tracked
-- in `device_user_merges`.
--
-- The merge does NOT roll backwards: if the user has imported MORE while
-- signed in than on this device, the device's lower count doesn't reset
-- them.
--
-- Run order: depends on 001_init.sql + 004_free_imports.sql.

create table if not exists public.device_user_merges (
  fingerprint_id text not null,
  user_id uuid not null references public.users(id) on delete cascade,
  merged_at timestamptz not null default now(),
  primary key (fingerprint_id, user_id)
);

-- RLS-on, same posture as device_imports / device_grants (audited by 007).
-- All access goes through the service-role backend; no client policies
-- needed.
alter table public.device_user_merges enable row level security;

create or replace function public.try_consume_free_import(
  p_user uuid,
  p_fingerprint text,
  p_allowance int
)
returns jsonb
language plpgsql
as $$
declare
  user_used int := 0;
  device_used int := 0;
  merge_inserted int := 0;
begin
  -- Make sure the device row exists, then lock it.
  insert into public.device_imports (fingerprint_id)
    values (p_fingerprint)
    on conflict (fingerprint_id) do nothing;

  select free_imports_used into device_used
    from public.device_imports
    where fingerprint_id = p_fingerprint
    for update;

  if p_user is not null then
    -- First time we see this (user, device) pair? Lift the account
    -- counter to max(account, device) so signed-out usage carries
    -- forward. The unique PK + ON CONFLICT DO NOTHING means subsequent
    -- imports from the same pair skip the merge step (and don't keep
    -- bumping the counter).
    insert into public.device_user_merges (fingerprint_id, user_id)
      values (p_fingerprint, p_user)
      on conflict (fingerprint_id, user_id) do nothing;
    get diagnostics merge_inserted = row_count;

    if merge_inserted > 0 then
      update public.users
        set free_imports_used = greatest(free_imports_used, device_used)
        where id = p_user;
    end if;

    select free_imports_used into user_used
      from public.users
      where id = p_user
      for update;
    if user_used is null then
      user_used := 0;
    end if;
  end if;

  if device_used >= p_allowance
     or (p_user is not null and user_used >= p_allowance) then
    return jsonb_build_object(
      'allowed', false,
      'user_used', user_used,
      'device_used', device_used,
      'allowance', p_allowance
    );
  end if;

  update public.device_imports
    set free_imports_used = free_imports_used + 1,
        last_seen_at = now()
    where fingerprint_id = p_fingerprint;

  if p_user is not null then
    update public.users
      set free_imports_used = free_imports_used + 1
      where id = p_user;
  end if;

  return jsonb_build_object(
    'allowed', true,
    'user_used', user_used + 1,
    'device_used', device_used + 1,
    'allowance', p_allowance
  );
end;
$$;

-- Re-pin search_path — `create or replace function` resets per-function
-- settings, so the 007_lint_security_fixes hardening has to be re-applied.
alter function public.try_consume_free_import(uuid, text, int) set search_path = '';
