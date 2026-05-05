-- Closes Supabase database-linter security findings:
--   - rls_disabled_in_public on device_imports / device_grants (ERROR)
--   - function_search_path_mutable on current_credits,
--     try_consume_free_cutout, try_consume_free_import (WARN)
--
-- Both tables are only accessed server-side via the service-role client,
-- which bypasses RLS. No app code uses the publishable/anon key against
-- them. No policies are needed — same pattern as users/subscriptions/
-- credit_ledger in 001_init.sql.

alter table public.device_imports enable row level security;
alter table public.device_grants  enable row level security;

-- Pin search_path to empty so any unqualified identifier inside the
-- function bodies must come from pg_catalog (always implicit). All
-- existing references inside these functions are already schema-
-- qualified (`public.users`, `public.credit_ledger`, etc.) and the only
-- unqualified calls are pg_catalog built-ins (`now`, `coalesce`, `sum`,
-- `jsonb_build_object`), so this is a no-op for behavior.

alter function public.current_credits(uuid)                    set search_path = '';
alter function public.try_consume_free_cutout(uuid, int)       set search_path = '';
alter function public.try_consume_free_import(uuid, text, int) set search_path = '';
