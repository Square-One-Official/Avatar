-- E14.9 — Pro-lijst beheerbaar vanuit de CMS (plan/E14-monetization.md).
--
-- Twee onafhankelijke stukken:
--   A. `payload.pro_access` — de nieuwe Payload-collectie. DDL 1:1 uit
--      Payload's eigen generator (`payload migrate:create`, offline snapshot
--      2026-08-01); kolomnamen/typen/indexen exact zoals de drizzle-adapter
--      ze at runtime verwacht. Het payload-schema is handmatig beheerd
--      (push: false), vandaar deze losse migratie.
--   B. `credit_ledger`-idempotentie voor de maandelijkse comp-grant, zelfde
--      patroon als de topup-index uit 002.
--
-- Volgorde: EERST deze migratie toepassen (Supabase SQL editor, als
-- postgres), DAARNA admin + backend deployen. Andersom faalt elke
-- pro-access-query in Payload (tabel bestaat niet) en valt de backend terug
-- op alleen `DEV_UNLIMITED_EMAILS`.
--
-- Idempotent en puur additief.

-- ---------------------------------------------------------------------------
-- A. payload.pro_access
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'payload' and t.typname = 'enum_pro_access_access'
  ) then
    create type payload.enum_pro_access_access as enum ('pro', 'unlimited');
  end if;
end $$;

create table if not exists payload.pro_access (
  "id" serial primary key not null,
  "email" varchar not null,
  "access" payload.enum_pro_access_access default 'pro' not null,
  "monthly_credits" numeric default 200,
  "active" boolean default true,
  "expires_at" timestamp(3) with time zone,
  "note" varchar,
  "granted_at" timestamp(3) with time zone,
  "updated_at" timestamp(3) with time zone default now() not null,
  "created_at" timestamp(3) with time zone default now() not null
);

-- Zelfde eigenaar als de rest van het payload-schema (zie 008), zodat de
-- scoped payload_app-rol zonder verhoogde rechten kan lezen/schrijven.
alter table payload.pro_access owner to payload_app;
alter type payload.enum_pro_access_access owner to payload_app;

create unique index if not exists pro_access_email_idx
  on payload.pro_access using btree ("email");
create index if not exists pro_access_active_idx
  on payload.pro_access using btree ("active");
create index if not exists pro_access_updated_at_idx
  on payload.pro_access using btree ("updated_at");
create index if not exists pro_access_created_at_idx
  on payload.pro_access using btree ("created_at");

-- Payload's document-locking join-tabel krijgt per collectie een kolom. Zonder
-- deze kolom faalt élke admin-query op pro-access (de adapter selecteert 'm
-- altijd mee), niet alleen het locken.
alter table payload.payload_locked_documents_rels
  add column if not exists "pro_access_id" integer;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'payload_locked_documents_rels_pro_access_fk'
  ) then
    alter table payload.payload_locked_documents_rels
      add constraint payload_locked_documents_rels_pro_access_fk
      foreign key ("pro_access_id") references payload.pro_access ("id")
      on delete cascade on update no action;
  end if;
end $$;

create index if not exists payload_locked_documents_rels_pro_access_id_idx
  on payload.payload_locked_documents_rels using btree ("pro_access_id");

-- ---------------------------------------------------------------------------
-- B. Idempotentie voor de maandelijkse comp-grant
-- ---------------------------------------------------------------------------
--
-- Een comped Pro (access = 'pro') heeft geen Stripe-subscription, dus de
-- webhook grant niets. De backend zet daarom zelf één ledger-rij per
-- kalendermaand met ref = 'comped:<user_id>:<YYYY-MM>'. Meerdere gelijktijdige
-- requests op de eerste call van de maand racen om die insert; de unieke index
-- laat er precies één winnen en de rest krijgt 23505, wat de backend inslikt.
--
-- Zelfde vorm als credit_ledger_reason_ref_topup_unique (002): (reason, ref)
-- uniek, ref is al globaal uniek doordat het user-id erin zit.
create unique index if not exists credit_ledger_reason_ref_comped_unique
  on public.credit_ledger (reason, ref)
  where ref is not null and reason = 'comped_pro';
