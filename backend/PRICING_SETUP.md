# Pricing Restructure — Manual Setup Steps

The code changes are deployed via Git. These steps must be done **once
in Stripe Dashboard + Vercel**, before the new build hits production.

## 1. Stripe Dashboard — create new Prices

Open <https://dashboard.stripe.com/products> and create the following:

### Pro Annual

- **Product:** existing "Pro" product (re-use it; do NOT make a new one)
- **Price:**
  - Amount: **€49,90**
  - Billing period: **Yearly**
  - Tax behavior: same as the existing monthly price (inclusive/exclusive)
- Copy the resulting `price_…` ID → goes into `PRICE_ID_PRO_ANNUAL`

### Top-up: 50 credits

- **Product:** new — "Avatars Credits — Starter"
- **Price:**
  - Amount: **€1,99**
  - Billing: **One-time**
- Copy the price ID → `PRICE_ID_TOPUP_50`

### Top-up: 750 credits

- **Product:** new — "Avatars Credits — Best Value"
- **Price:**
  - Amount: **€14,99**
  - Billing: **One-time**
- Copy the price ID → `PRICE_ID_TOPUP_750`

> The existing €4,99 / 200 credits Price stays unchanged (`PRICE_ID_TOPUP_200`).

## 2. Vercel — add env vars

`vercel env add` for project `avatars-api` (rootDirectory=backend),
target = Production AND Preview:

```
PRICE_ID_PRO_ANNUAL=price_…
PRICE_ID_TOPUP_50=price_…
PRICE_ID_TOPUP_750=price_…
CRON_SECRET=<generate with: openssl rand -base64 32>
```

The CRON_SECRET protects `/api/cron/grant-yearly-credits` from being
called externally. Vercel automatically sends `Authorization: Bearer
$CRON_SECRET` to cron endpoints on the configured schedule.

## 3. Verify cron registration

After deploy, check <https://vercel.com/[org]/avatars-api/settings/cron-jobs>
— you should see:

- **Path:** `/api/cron/grant-yearly-credits`
- **Schedule:** `0 3 1 * *` (1st of every month, 03:00 UTC)

## 4. Pre-launch verification — Replicate cost check

Go to <https://replicate.com/account/billing> and pull the
`851-labs/background-remover` (BiRefNet) per-call cost from your last
month's invoice.

- **Cost ≤ €0,005 / call** → all 3 packs ≥ 70% margin (planned).
- **€0,005 < cost ≤ €0,015 / call** → margins drop but stay positive.
  The €14,99 / 750 credits "Best Value" pack approaches break-even at
  the upper bound — consider raising it to €17,99 OR dropping to 600
  credits.
- **Cost > €0,015 / call** → revisit pack pricing across the board
  before announcing the new structure.

## 5. Post-deploy smoke test

```bash
# 1. Yearly subscribe link
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"interval":"year"}' \
  https://api.aaavatar.nl/v1/checkout/subscribe
# → expects { "url": "https://checkout.stripe.com/..." } where the
#   resulting Stripe Checkout shows €49,90/year.

# 2. Each pack
for pack in credits50 credits200 credits750; do
  echo "=== $pack ==="
  curl -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"pack\":\"$pack\"}" \
    https://api.aaavatar.nl/v1/checkout/topup
done

# 3. Cron endpoint (should 401 without secret)
curl https://api.aaavatar.nl/api/cron/grant-yearly-credits
# → { "error": "unauthorized" }
curl -H "Authorization: Bearer $CRON_SECRET" \
  https://api.aaavatar.nl/api/cron/grant-yearly-credits
# → { "processed": N, "granted": M, "skipped": K, "errors": [] }
```

## 6. Rollback plan

If anything goes sideways:

- The new Stripe Prices coexist with the old one — they don't break
  the previous build's checkout flow. The old €4,99/mo `PRICE_ID_PRO`
  still works.
- Removing `PRICE_ID_PRO_ANNUAL` from Vercel env vars + redeploying
  causes the yearly button in the new app to surface
  `pricing_misconfigured` — but monthly keeps working. Users just see
  an error if they tap Yearly.
- The new pack IDs (`credits50`, `credits750`) gracefully 500 with
  `pricing_misconfigured` if the env vars aren't set, so you can ship
  the code first and switch packs on by adding env vars.
