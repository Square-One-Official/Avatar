# AGENTS.md

## Cursor Cloud specific instructions

This is a monorepo for **Aaavatar**: a native macOS HR portrait app plus its cloud "Pro" stack.
Only part of it runs on the Linux Cloud VM:

| Component | Path | Runnable on this Linux VM? |
|-----------|------|----------------------------|
| macOS app (Avatar) | `Avatar/`, `Avatar.xcodeproj`, `project.yml` | **No** — needs macOS 14+ and Xcode. Do not attempt to build/run here. |
| Backend API (avatars-api) | `backend/` | Partially — automated checks + individual handlers run; full `vercel dev` needs a Vercel login/token + external secrets. |
| Admin CMS (avatar-admin) | `admin/` | **Yes** — Next.js 15 + Payload CMS v3, runs fully locally against a local Postgres. |

The update script only runs `npm install` in `backend/` and `admin/`. Everything below (Postgres, `.env`, schema bootstrap) is a manual, per-VM setup step — it is intentionally kept out of the update script.

### Backend (`backend/`, "avatars-api")

- Standard commands live in `backend/package.json` and `backend/README.md`.
- Automated checks (this service's CI): `npm run typecheck` (tsc) and `npx tsx scripts/models-smoke.ts`. Both run with no secrets.
- `npm run dev` is `vercel dev`, which **requires Vercel credentials** (`vercel login` or `--token`) and a linked project — it fails with "No existing credentials found" otherwise. Most endpoints also need external services (Supabase, Stripe, Replicate) from `.env` (see `backend/.env.example`).
- To smoke-test a single serverless function without Vercel, invoke its default handler directly with `tsx` and a mock `req`/`res` (the handler signature is `(VercelRequest, VercelResponse)`). `api/appcast.ts` is fully self-contained (reads `api/_appcast.xml`, no external deps) and is a good target.

### Admin CMS (`admin/`, "avatar-admin") — runs locally

Standard commands are in `admin/package.json` / `admin/README.md`. Non-obvious caveats for running it here:

- **Postgres is required and is not preinstalled.** Install + start it once per VM (`apt-get install postgresql`, `pg_ctlcluster 16 main start`). Create a `payload_app` login role that owns a `payload` schema, then point `PAYLOAD_DATABASE_URL` at it (direct port 5432, not a pooler).
- **`.env` is gitignored.** Create `admin/.env` from `admin/.env.example`. For a local run only `PAYLOAD_SECRET`, `PAYLOAD_DATABASE_URL`, `ADMIN_TOTP_SECRET`, and `ADMIN_MFA_SIGNING_SECRET` are needed. Generate the two MFA secrets with `node scripts/setup-mfa.mjs`. `PAYLOAD_PUBLIC_SERVER_URL=http://localhost:3001` locally.
- **Schema is NOT auto-created** (`payload.config.ts` sets `push: false`). The repo ships no migrations. Bootstrap a fresh local DB with `npx payload migrate:create` then `npx payload migrate` (the generated file under `admin/src/migrations/` is a local dev artifact — leave it untracked, don't commit it). The Payload CLI does not auto-load `.env`, so export it first (e.g. `set -a && . ./.env && set +a`).
- If the admin logs "you may need to run `payload generate:importmap`" (rich-text / S3 client components), run `npx payload generate:importmap`. Note the committed `admin/src/app/(payload)/admin/importMap.js` is an intentional empty placeholder — regenerate locally if needed but don't commit the change.
- **MFA gate:** the admin sits behind a TOTP step (`middleware.ts`). Browser flow: hit `/admin` → redirected to `/mfa` → enter the current 6-digit TOTP for `ADMIN_TOTP_SECRET`. The `mfa-session` cookie is `Secure` but works on `http://localhost` (Chrome treats localhost as a secure context). To pass it headlessly, `POST {"code":"<totp>"}` to `/api/mfa/verify` and reuse the returned `Set-Cookie`. Machine-to-machine `Authorization: users API-Key …` requests bypass the gate.
- Dev server: `npm run dev` serves the admin at `http://localhost:3001/admin`. First run shows Payload's "create first user" screen.
- Optional integrations (Resend newsletters, Upstash rate limiting, Supabase S3 media storage) **fail open** when their env vars are unset — the admin still runs; only those specific features are disabled.
