-- 014_newsletter_double_optin.sql (E17.6) — GATED, niet autonoom gedraaid.
-- Double-opt-in ledger voor Nieuwsbrief 2.0. Additief en NIET-destructief:
-- bestaande nieuwsbrief-flow (newsletter_cohorts-view + newsletter-unsubscribes)
-- blijft werken; deze tabel registreert losstaand de expliciete opt-in-
-- bevestiging (welkom-na-OTP, re-engagement). De confirm-endpoint
-- (/v1/newsletter/confirm) upsert't hierin; de dispatch kan er optioneel op
-- filteren (zie admin/NIEUWSBRIEF-2.0.md) — standaard ongewijzigd gedrag.

create table if not exists public.newsletter_optins (
    email        text primary key,
    requested_at timestamptz not null default now(),
    confirmed_at timestamptz,
    source       text not null default 'v2_onboarding'
);

-- De backend (service-role) schrijft hierin via de confirm-endpoint.
-- De admin (scoped payload_app-role) heeft alleen SELECT nodig voor de
-- optionele recipient-filtering; geen publieke (anon/authenticated) grants.
revoke all on public.newsletter_optins from anon, authenticated;
-- grant select on public.newsletter_optins to payload_app;  -- ontgrendel bij filter-integratie

comment on table public.newsletter_optins is
    'E17.6 double-opt-in ledger: confirmed_at not null = bevestigde nieuwsbrief-opt-in.';
