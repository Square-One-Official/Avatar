-- Avatars API — free Magic Cutout trial.
-- Free users get a small allowance of cloud cutouts so they can see the
-- BiRefNet quality on their own photos before paying. The cap is enforced
-- server-side (not via the credit ledger) so reinstall / sign-out can't
-- reset the counter. Pro users continue to use the credit_ledger flow.

alter table public.users
  add column if not exists free_cutouts_used int not null default 0;

-- Atomically claims one free-trial cutout slot for the user. Returns the
-- new value of `free_cutouts_used` if the slot was granted, or NULL if
-- the user has already exhausted the allowance. Single-statement update
-- means concurrent calls can't both squeeze past the cap.
create or replace function public.try_consume_free_cutout(
  p_user uuid,
  p_allowance int
)
returns int
language sql
as $$
  update public.users
     set free_cutouts_used = free_cutouts_used + 1
   where id = p_user
     and free_cutouts_used < p_allowance
  returning free_cutouts_used;
$$;
