-- Closes Supabase database-linter findings on the newsletter cohort
-- objects shipped in 010_newsletter_cohorts_view.sql:
--
--   auth_users_exposed                              (ERROR)
--   materialized_view_in_api                        (WARN)
--   anon_security_definer_function_executable      (WARN)
--   authenticated_security_definer_function_executable (WARN)
--
-- Root cause: `public.newsletter_cohorts` and
-- `public.refresh_newsletter_cohorts()` were created in the `public`
-- schema, which PostgREST exposes over `/rest/v1`. Supabase ships
-- default grants that give `anon` + `authenticated` SELECT on every
-- table/view in `public` and EXECUTE on every function (the latter is
-- also a Postgres default — functions are EXECUTE-to-PUBLIC unless
-- revoked). Migration 010 only added the explicit `payload_app` grants
-- and never revoked the inherited public ones, so anon/authenticated
-- can read user emails via /rest/v1/newsletter_cohorts and trigger a
-- refresh via /rest/v1/rpc/refresh_newsletter_cohorts.
--
-- The fix is to revoke from anon/authenticated/PUBLIC and keep only
-- the `payload_app` grants that the admin actually uses (see
-- `admin/src/lib/recipients.ts`). The backend itself uses the service
-- role and bypasses these grants entirely.

revoke all on public.newsletter_cohorts from anon, authenticated, public;
revoke all on function public.refresh_newsletter_cohorts() from anon, authenticated, public;
