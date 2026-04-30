-- Avatars API — v1 extensions.
-- Adds:
--   1. The 'pro' tier (single-tier subscription, replaces starter/plus/studio
--      in the v1 client UI; legacy tiers stay valid so existing data is fine).
--   2. Idempotency on one-time topup credit grants — same shape as the
--      existing period_renewal idempotency (reason+ref unique).

alter table public.subscriptions
  drop constraint if exists subscriptions_tier_check;

alter table public.subscriptions
  add constraint subscriptions_tier_check
  check (tier in ('starter', 'plus', 'studio', 'pro'));

-- Topup packs are one-time Stripe Checkout invoices; webhook retries can
-- replay invoice.paid for the same invoice id. Same idempotency pattern as
-- period_renewal: (reason, ref) unique where ref is set.
create unique index if not exists credit_ledger_reason_ref_topup_unique
  on public.credit_ledger (reason, ref)
  where ref is not null and reason = 'topup_pack';
