# Avatars API — backend for the Pro features

Minimal Vercel + Supabase backend that:

1. Authenticates users via Supabase (Google OAuth hergebruikt uit de macOS app).
2. Handles Stripe Checkout + webhooks for the Pro subscription and credit top-ups.
3. Tracks credits in Postgres (single source of truth: `credit_ledger`).
4. Proxies Replicate for Magic Cutout and deducts one credit per successful run.

## Stack

- **Runtime:** Vercel (Node.js functions — not Edge, because `sharp` is needed for image work)
- **DB + Auth:** Supabase (Postgres + built-in Google OAuth)
- **Payments:** Stripe Checkout + Customer Portal
- **AI:** Replicate `851-labs/background-remover`

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET  | `/v1/account` | Current tier + credits + renewal date |
| POST | `/v1/checkout/subscribe` | Create Stripe Checkout Session for the Pro plan |
| POST | `/v1/checkout/topup` | Create Stripe Checkout Session for a credit top-up |
| POST | `/api/portal` | Stripe Customer Portal URL (manage / cancel) |
| POST | `/v1/cutout` | Magic Cutout; deduct one credit |
| POST | `/api/stripe-webhook` | Stripe → Supabase sync (subscription, invoices) |

All user-facing endpoints expect an `Authorization: Bearer <supabase-jwt>` header.
`/api/stripe-webhook` is verified via the Stripe webhook signing secret.

## Setup

1. Create a Supabase project; enable Google OAuth provider. Set redirect URL to `aaavatar://auth-callback`.
2. Run the SQL in [`sql/001_init.sql`](sql/001_init.sql) via the Supabase SQL editor.
3. Create a Stripe account. In **test mode**, create the Pro product with a monthly recurring EUR price. Note the price ID.
4. Create a webhook endpoint in Stripe pointing to `https://api.aaavatar.nl/api/stripe-webhook`. Subscribe to `checkout.session.completed`, `customer.subscription.created/updated/deleted`, `invoice.paid`.
5. Create a Replicate account and generate an API token.
6. Copy [`.env.example`](.env.example) to `.env` and fill in secrets. Add the same keys in Vercel's project settings.
7. `npm install && vercel dev` voor lokaal testen; `vercel --prod` voor productie.
