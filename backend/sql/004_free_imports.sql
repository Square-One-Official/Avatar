-- Avatars API — anti-cheat for the 5-portrait free tier cap.
-- Three layers, all evaluated by `try_consume_free_import`:
--   1. Per-account counter (`users.free_imports_used`) — survives reinstall
--      as long as the user signs back in to the same Google account.
--   2. Per-device counter (`device_imports`) — fingerprint is a UUID stored
--      in the macOS Keychain; survives reinstall, blocks "create a new
--      Google account to reset" cheating. No hardware identifiers, so an
--      org's IT can't object to system-level snooping.
--   3. Anonymous device cap — when no user is signed in, only the device
--      counter applies; sign-in later still hits the device cap.

alter table public.users
  add column if not exists free_imports_used int not null default 0;

create table if not exists public.device_imports (
  fingerprint_id text primary key,
  free_imports_used int not null default 0,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

-- Atomic gate: returns whether the import is allowed and the new counters.
-- p_user is NULL for anonymous (signed-out) callers — only the device
-- counter applies in that case.
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
