-- E43.2 — eenmalige credit-refund voor de generate-background-outage (A2).
--
-- Context: prod draaide de 27-jun-iteratie van /v1/generate-background
-- (charge vóór delivery, oude response-shape) terwijl de client het nieuwe
-- signed-URL-contract sprak. Elke poging faalde client-side met
-- "Unexpected server response." maar de charge (-2 of -3 credits, reason
-- 'generate_background') stond al in credit_ledger. Dit script boekt alle
-- generate_background-charges van de laatste 48 uur terug.
--
-- Eigenschappen:
--   * Ledger is append-only: refund = nieuwe POSITIEVE rij, we muteren niets.
--   * reason = 'refund_e43_generate_background_outage' → traceerbaar.
--   * ref = id van de teruggeboekte charge-rij → idempotent: het script
--     nogmaals draaien refundt dezelfde charge nooit twee keer (NOT EXISTS).
--   * current_credits() telt binnen de lopende periode op created_at >=
--     current_period_start; de refund-rijen krijgen now() en tellen dus
--     direct mee in het saldo van de gebruiker.
--
-- GEBRUIK (in volgorde, via Supabase SQL editor of psql met service role):
--   1. Draai ALLEEN stap 1 (dry-run) en controleer aantal + totaal.
--   2. Draai daarna stap 2 binnen de transactie; vergelijk de RETURNING-
--      aantallen met de dry-run vóór COMMIT.

-- ---------------------------------------------------------------------------
-- STAP 1 — DRY RUN: hoeveel charges, hoeveel credits, hoeveel gebruikers?
-- Verwacht (audit 2026-07-01): een handvol rijen à 2-3 credits.
-- ---------------------------------------------------------------------------
select
  count(*)                            as charges_to_refund,
  coalesce(sum(-c.delta), 0)          as credits_to_refund,
  count(distinct c.user_id)           as users_affected,
  min(c.created_at)                   as oldest_charge,
  max(c.created_at)                   as newest_charge
from public.credit_ledger c
where c.reason = 'generate_background'
  and c.delta < 0
  and c.created_at >= now() - interval '48 hours'
  and not exists (
    select 1
    from public.credit_ledger r
    where r.reason = 'refund_e43_generate_background_outage'
      and r.ref = c.id::text
  );

-- Detail-variant van de dry-run (per gebruiker), voor de Result-regel:
select
  c.user_id,
  count(*)                   as charges,
  coalesce(sum(-c.delta), 0) as credits_back
from public.credit_ledger c
where c.reason = 'generate_background'
  and c.delta < 0
  and c.created_at >= now() - interval '48 hours'
  and not exists (
    select 1
    from public.credit_ledger r
    where r.reason = 'refund_e43_generate_background_outage'
      and r.ref = c.id::text
  )
group by c.user_id
order by credits_back desc;

-- ---------------------------------------------------------------------------
-- STAP 2 — REFUND (pas draaien ná akkoord op de dry-run; NIET automatisch).
-- Idempotent: reeds gerefunde charges (ref-match) worden overgeslagen.
-- ---------------------------------------------------------------------------
-- begin;
--
-- insert into public.credit_ledger (user_id, delta, reason, ref)
-- select
--   c.user_id,
--   -c.delta,                                        -- charge -2 → refund +2
--   'refund_e43_generate_background_outage',
--   c.id::text                                       -- koppelt refund ↔ charge
-- from public.credit_ledger c
-- where c.reason = 'generate_background'
--   and c.delta < 0
--   and c.created_at >= now() - interval '48 hours'
--   and not exists (
--     select 1
--     from public.credit_ledger r
--     where r.reason = 'refund_e43_generate_background_outage'
--       and r.ref = c.id::text
--   )
-- returning id, user_id, delta, ref;
--
-- -- Controle: moet 0 zijn (alles gerefund) vóór commit.
-- select count(*) as remaining_unrefunded
-- from public.credit_ledger c
-- where c.reason = 'generate_background'
--   and c.delta < 0
--   and c.created_at >= now() - interval '48 hours'
--   and not exists (
--     select 1
--     from public.credit_ledger r
--     where r.reason = 'refund_e43_generate_background_outage'
--       and r.ref = c.id::text
--   );
--
-- commit;
