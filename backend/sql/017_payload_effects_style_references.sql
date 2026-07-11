-- E54.1 — CMS-stijlreferenties voor Effects (plan/E54-effect-stijlreferenties.md).
-- Het nieuwe Payload-arrayveld `styleReferences` op de Effects-collectie krijgt
-- van de drizzle-adapter een eigen tabel. DDL 1:1 overgenomen uit Payload's
-- eigen generator (`payload migrate:create`, offline snapshot 2026-07-04) —
-- kolomnamen, typen en indexen exact zoals de adapter ze at runtime verwacht.
-- Het payload-schema wordt handmatig beheerd (push: false in
-- admin/src/payload.config.ts), vandaar deze losse migratie.
--
-- Volgorde: EERST deze migratie toepassen (Supabase SQL editor, als postgres),
-- DAARNA de admin deployen. Andersom breekt elke effects-query in Payload
-- (join op een ontbrekende tabel) en valt /v1/effects terug op de fallback.
--
-- Idempotent en puur additief: bestaande tabellen worden niet aangeraakt.

create table if not exists payload.effects_style_references (
  "_order" integer not null,
  "_parent_id" integer not null,
  "id" varchar primary key not null,
  "image_id" integer not null
);

-- Zelfde eigenaar als de rest van het payload-schema (zie 008), zodat de
-- scoped payload_app-rol zonder verhoogde rechten kan lezen/schrijven.
alter table payload.effects_style_references owner to payload_app;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'effects_style_references_image_id_media_id_fk'
  ) then
    alter table payload.effects_style_references
      add constraint effects_style_references_image_id_media_id_fk
      foreign key ("image_id") references payload.media ("id")
      on delete set null on update no action;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'effects_style_references_parent_id_fk'
  ) then
    alter table payload.effects_style_references
      add constraint effects_style_references_parent_id_fk
      foreign key ("_parent_id") references payload.effects ("id")
      on delete cascade on update no action;
  end if;
end $$;

create index if not exists effects_style_references_order_idx
  on payload.effects_style_references using btree ("_order");
create index if not exists effects_style_references_parent_id_idx
  on payload.effects_style_references using btree ("_parent_id");
create index if not exists effects_style_references_image_idx
  on payload.effects_style_references using btree ("image_id");
