-- Audit finding CRITICAL #1: the admin (Payload CMS) and backend
-- (avatars-api) currently load the same SUPABASE_SERVICE_ROLE_KEY, which
-- bypasses RLS — compromise of either deployable equals full database
-- access. This migration confines Payload's Postgres user to its own
-- `payload` schema so the admin no longer needs the service role for
-- database access.
--
-- After applying:
--   1. Set the role's password from the Supabase SQL editor (the password
--      is intentionally not in this migration so it isn't committed to
--      git):
--          ALTER ROLE payload_app WITH PASSWORD '<32-random-bytes>';
--   2. Build the connection string. Prefer the direct (non-pooled) port
--      because Payload migrations rely on prepared statements / LISTEN
--      which pgbouncer's transaction mode breaks:
--          postgresql://payload_app:<password>@db.<project>.supabase.co:5432/postgres?schema=payload
--   3. Add PAYLOAD_DATABASE_URL to the admin Vercel project (Production +
--      Preview environments). Keep SUPABASE_SERVICE_ROLE_KEY there for now
--      — `recipients.ts` still needs it for newsletter cohort resolution.
--      Audit finding HIGH #12 tracks moving cohort resolution onto this
--      scoped role so the admin can drop the service role entirely.
--   4. Redeploy admin. Once /admin loads and a Payload migration succeeds
--      against the new role, the service-role grant on the Payload schema
--      can be revoked further (DROP ROLE service_role grants on payload.*).

-- 1. The role: LOGIN so it can connect, NOINHERIT so it doesn't pick up
--    grants made to PUBLIC, no superuser, no bypassrls. Idempotent so the
--    migration can be re-run safely.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'payload_app') then
    create role payload_app with login noinherit nobypassrls;
  end if;
end $$;

-- 2. Schema ownership. Payload auto-creates `payload` on first deploy with
--    `push: true`, owned by whichever role made the connection (currently
--    the service role / postgres). Reassigning ownership lets the scoped
--    role run future `payload migrate` DDL without elevated privileges.
do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'payload') then
    create schema payload authorization payload_app;
  else
    alter schema payload owner to payload_app;
  end if;
end $$;

-- 3. Reassign every existing object inside the `payload` schema to the new
--    owner. `REASSIGN OWNED BY` is too broad (it would also move tables in
--    `public.*` owned by the old role), so we enumerate per relkind.
--    Sequences need ALTER SEQUENCE; tables/views/matviews/foreign/partitioned
--    accept ALTER TABLE.
do $$
declare
  rec record;
begin
  for rec in
    select c.oid::regclass::text as objname, c.relkind
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'payload'
      and c.relkind in ('r','v','m','f','p','S')
  loop
    if rec.relkind = 'S' then
      execute format('alter sequence %s owner to payload_app', rec.objname);
    else
      execute format('alter table %s owner to payload_app', rec.objname);
    end if;
  end loop;
end $$;

do $$
declare
  rec record;
begin
  for rec in
    select p.oid::regprocedure::text as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'payload'
  loop
    execute format('alter function %s owner to payload_app', rec.sig);
  end loop;
end $$;

do $$
declare
  rec record;
begin
  for rec in
    select t.oid::regtype::text as typname
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'payload'
      and t.typtype in ('e','c','d')
  loop
    execute format('alter type %s owner to payload_app', rec.typname);
  end loop;
end $$;

-- 4. Grants inside the payload schema. Owner already has full rights; we
--    set DEFAULT PRIVILEGES so future objects created by `payload migrate`
--    are owned by payload_app and grants don't need to be re-applied.
grant usage, create on schema payload to payload_app;
alter default privileges in schema payload grant all on tables to payload_app;
alter default privileges in schema payload grant all on sequences to payload_app;
alter default privileges in schema payload grant all on functions to payload_app;

-- 5. Hard wall against the public + auth schemas. Postgres defaults are
--    already restrictive at the table level (table grants required for
--    SELECT), but a fresh Supabase project has `GRANT USAGE ON SCHEMA
--    public TO PUBLIC` and `CREATE TABLE` for the public role, which the
--    new role would inherit. Explicit REVOKEs pin the boundary so a
--    future Supabase upgrade can't silently extend privileges.
revoke create on schema public from payload_app;
revoke all on schema auth from payload_app;

-- 6. search_path. Setting it on the role means every connection initiated
--    by payload_app starts with `payload` first, so unqualified references
--    resolve to the right schema. Excluding `public` defangs accidental
--    cross-schema leaks via unqualified table references in
--    user-authored SQL.
alter role payload_app set search_path = 'payload', 'pg_catalog';

-- 7. Sanity check (informational only — does not block the migration). If
--    the role still owns anything outside `payload`, that's a sign the
--    enumeration above missed an object kind; investigate before relying
--    on the new isolation.
do $$
declare
  leak_count int;
begin
  select count(*) into leak_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relowner = (select oid from pg_roles where rolname = 'payload_app')
    and n.nspname <> 'payload';
  if leak_count > 0 then
    raise warning 'payload_app owns % object(s) outside the payload schema — review pg_class', leak_count;
  end if;
end $$;
