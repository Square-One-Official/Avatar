-- E55-uitrol (2026-08-03) — catch-up: Messages + Banner Presets ontbraken op prod.
--
-- Oorzaak: de payload-schema is gevormd in het push:true-tijdperk (t/m 358b211,
-- 2026-06-23); collecties van daarna kregen handmatige DDL (017/018) — behalve
-- Messages (E17, push faalde stil) en BannerPresets (E39). De huidige admin
-- enumereert ALLE collecties in de locked-documents-query, dus de twee
-- ontbrekende rels-kolommen maakten élke detail-pagina zwart (E55-uitrol-vondst).
--
-- DDL 1:1 uit de offline `payload migrate:create`-snapshot (2026-08-03),
-- idempotent gemaakt (zelfde patroon als sql/018). Extra v1-tijdperk-tabellen
-- (backgrounds, hair/clothes/face, globals) blijven bewust staan.


-- 1. Enums (idempotent via duplicate_object-guard).

do $$ begin
  CREATE TYPE "payload"."enum_messages_channel" AS ENUM('inApp', 'email', 'both');
exception when duplicate_object then null;
end $$;

do $$ begin
  CREATE TYPE "payload"."enum_messages_targeting_cohort" AS ENUM('all', 'freeUsers', 'proUsers', 'specificEmails');
exception when duplicate_object then null;
end $$;

do $$ begin
  CREATE TYPE "payload"."enum_messages_targeting_platform" AS ENUM('all', 'macos');
exception when duplicate_object then null;
end $$;

do $$ begin
  CREATE TYPE "payload"."enum_messages_schedule_frequency" AS ENUM('once', 'everySignInUntilDismissed', 'untilDate', 'delayedNthSignIn');
exception when duplicate_object then null;
end $$;

do $$ begin
  CREATE TYPE "payload"."enum_banner_presets_category" AS ENUM('default', 'minimal', 'bold', 'playful', 'gradient');
exception when duplicate_object then null;
end $$;


-- 2. Tabellen.

CREATE TABLE IF NOT EXISTS "payload"."messages_targeting_audience_emails" (
  	"_order" integer NOT NULL,
  	"_parent_id" integer NOT NULL,
  	"id" varchar PRIMARY KEY NOT NULL,
  	"email" varchar
  );

CREATE TABLE IF NOT EXISTS "payload"."messages_badge_targets" (
  	"_order" integer NOT NULL,
  	"_parent_id" integer NOT NULL,
  	"id" varchar PRIMARY KEY NOT NULL,
  	"component_id_id" integer NOT NULL,
  	"duration_days" numeric DEFAULT 14 NOT NULL
  );

CREATE TABLE IF NOT EXISTS "payload"."messages" (
  	"id" serial PRIMARY KEY NOT NULL,
  	"title" varchar NOT NULL,
  	"slug" varchar NOT NULL,
  	"channel" "payload"."enum_messages_channel" DEFAULT 'inApp' NOT NULL,
  	"body" jsonb,
  	"image_id" integer,
  	"primary_cta_label" varchar,
  	"primary_cta_url" varchar,
  	"targeting_cohort" "payload"."enum_messages_targeting_cohort" DEFAULT 'all' NOT NULL,
  	"targeting_signup_after" timestamp(3) with time zone,
  	"targeting_signup_before" timestamp(3) with time zone,
  	"targeting_min_app_version" varchar,
  	"targeting_platform" "payload"."enum_messages_targeting_platform" DEFAULT 'all',
  	"schedule_frequency" "payload"."enum_messages_schedule_frequency" DEFAULT 'once' NOT NULL,
  	"schedule_until_date" timestamp(3) with time zone,
  	"schedule_delay_n" numeric,
  	"schedule_published_at" timestamp(3) with time zone,
  	"schedule_expires_at" timestamp(3) with time zone,
  	"newsletter_subject" varchar,
  	"newsletter_from_name" varchar,
  	"newsletter_custom_body" jsonb,
  	"newsletter_sent_at" timestamp(3) with time zone,
  	"updated_at" timestamp(3) with time zone DEFAULT now() NOT NULL,
  	"created_at" timestamp(3) with time zone DEFAULT now() NOT NULL
  );

CREATE TABLE IF NOT EXISTS "payload"."banner_presets" (
  	"id" serial PRIMARY KEY NOT NULL,
  	"key" varchar NOT NULL,
  	"label" varchar NOT NULL,
  	"category" "payload"."enum_banner_presets_category" DEFAULT 'default',
  	"thumbnail_id" integer,
  	"config" varchar NOT NULL,
  	"order" numeric DEFAULT 99,
  	"active" boolean DEFAULT true,
  	"updated_at" timestamp(3) with time zone DEFAULT now() NOT NULL,
  	"created_at" timestamp(3) with time zone DEFAULT now() NOT NULL
  );


-- 3. Ontbrekende kolommen op payload_locked_documents_rels.

ALTER TABLE "payload"."payload_locked_documents_rels" ADD COLUMN IF NOT EXISTS "messages_id" integer;

ALTER TABLE "payload"."payload_locked_documents_rels" ADD COLUMN IF NOT EXISTS "banner_presets_id" integer;


-- 4. Foreign keys (guarded op constraint-naam, sql/018-patroon).

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'messages_targeting_audience_emails_parent_id_fk') then
    ALTER TABLE "payload"."messages_targeting_audience_emails" ADD CONSTRAINT "messages_targeting_audience_emails_parent_id_fk" FOREIGN KEY ("_parent_id") REFERENCES "payload"."messages"("id") ON DELETE cascade ON UPDATE no action;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'messages_badge_targets_component_id_id_badge_components_id_fk') then
    ALTER TABLE "payload"."messages_badge_targets" ADD CONSTRAINT "messages_badge_targets_component_id_id_badge_components_id_fk" FOREIGN KEY ("component_id_id") REFERENCES "payload"."badge_components"("id") ON DELETE set null ON UPDATE no action;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'messages_badge_targets_parent_id_fk') then
    ALTER TABLE "payload"."messages_badge_targets" ADD CONSTRAINT "messages_badge_targets_parent_id_fk" FOREIGN KEY ("_parent_id") REFERENCES "payload"."messages"("id") ON DELETE cascade ON UPDATE no action;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'messages_image_id_media_id_fk') then
    ALTER TABLE "payload"."messages" ADD CONSTRAINT "messages_image_id_media_id_fk" FOREIGN KEY ("image_id") REFERENCES "payload"."media"("id") ON DELETE set null ON UPDATE no action;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'banner_presets_thumbnail_id_media_id_fk') then
    ALTER TABLE "payload"."banner_presets" ADD CONSTRAINT "banner_presets_thumbnail_id_media_id_fk" FOREIGN KEY ("thumbnail_id") REFERENCES "payload"."media"("id") ON DELETE set null ON UPDATE no action;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'payload_locked_documents_rels_messages_fk') then
    ALTER TABLE "payload"."payload_locked_documents_rels" ADD CONSTRAINT "payload_locked_documents_rels_messages_fk" FOREIGN KEY ("messages_id") REFERENCES "payload"."messages"("id") ON DELETE cascade ON UPDATE no action;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'payload_locked_documents_rels_banner_presets_fk') then
    ALTER TABLE "payload"."payload_locked_documents_rels" ADD CONSTRAINT "payload_locked_documents_rels_banner_presets_fk" FOREIGN KEY ("banner_presets_id") REFERENCES "payload"."banner_presets"("id") ON DELETE cascade ON UPDATE no action;
  end if;
end $$;


-- 5. Indexen.

CREATE INDEX IF NOT EXISTS "messages_targeting_audience_emails_order_idx" ON "payload"."messages_targeting_audience_emails" USING btree ("_order");

CREATE INDEX IF NOT EXISTS "messages_targeting_audience_emails_parent_id_idx" ON "payload"."messages_targeting_audience_emails" USING btree ("_parent_id");

CREATE INDEX IF NOT EXISTS "messages_badge_targets_order_idx" ON "payload"."messages_badge_targets" USING btree ("_order");

CREATE INDEX IF NOT EXISTS "messages_badge_targets_parent_id_idx" ON "payload"."messages_badge_targets" USING btree ("_parent_id");

CREATE INDEX IF NOT EXISTS "messages_badge_targets_component_id_idx" ON "payload"."messages_badge_targets" USING btree ("component_id_id");

CREATE UNIQUE INDEX IF NOT EXISTS "messages_slug_idx" ON "payload"."messages" USING btree ("slug");

CREATE INDEX IF NOT EXISTS "messages_image_idx" ON "payload"."messages" USING btree ("image_id");

CREATE INDEX IF NOT EXISTS "messages_updated_at_idx" ON "payload"."messages" USING btree ("updated_at");

CREATE INDEX IF NOT EXISTS "messages_created_at_idx" ON "payload"."messages" USING btree ("created_at");

CREATE UNIQUE INDEX IF NOT EXISTS "banner_presets_key_idx" ON "payload"."banner_presets" USING btree ("key");

CREATE INDEX IF NOT EXISTS "banner_presets_thumbnail_idx" ON "payload"."banner_presets" USING btree ("thumbnail_id");

CREATE INDEX IF NOT EXISTS "banner_presets_updated_at_idx" ON "payload"."banner_presets" USING btree ("updated_at");

CREATE INDEX IF NOT EXISTS "banner_presets_created_at_idx" ON "payload"."banner_presets" USING btree ("created_at");
