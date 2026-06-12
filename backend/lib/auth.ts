import { createRemoteJWKSet, jwtVerify } from "jose";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

const SUPABASE_URL = process.env.SUPABASE_URL!;

// Supabase new-key architecture: access tokens are signed with an ECC P-256
// key published at /auth/v1/.well-known/jwks.json. Legacy HS256 JWT shared
// secret is intentionally not supported — project must have legacy JWT-based
// API keys disabled in Settings → API Keys.
const JWKS = createRemoteJWKSet(new URL(`${SUPABASE_URL}/auth/v1/.well-known/jwks.json`));

export type AuthedUser = {
  id: string;
  email?: string;
};

export async function requireUser(
  req: VercelRequest,
  res: VercelResponse,
): Promise<AuthedUser | null> {
  const header = req.headers.authorization ?? "";
  const m = header.match(/^Bearer\s+(.+)$/i);
  if (!m) {
    res.status(401).json({ error: "Missing Authorization header" });
    return null;
  }
  const token = m[1];

  const payload = await verifyToken(token);
  if (!payload) {
    res.status(401).json({ error: "Invalid or expired token" });
    return null;
  }
  const sub = typeof payload.sub === "string" ? payload.sub : null;
  if (!sub) {
    res.status(401).json({ error: "Invalid token" });
    return null;
  }
  const email = typeof payload.email === "string" ? payload.email : undefined;
  return { id: sub, email };
}

/**
 * Like `requireUser`, but resolves to null when no Authorization header is
 * present instead of writing a 401. Used by endpoints (notably
 * `/v1/import-claim`) that gate anonymous callers via a device-only
 * counter. An invalid/expired token is still a hard 401 — we don't want
 * to silently drop bad tokens to anonymous mode and bypass per-account
 * caps.
 */
export async function optionalUser(
  req: VercelRequest,
  res: VercelResponse,
): Promise<AuthedUser | null | "rejected"> {
  const header = req.headers.authorization ?? "";
  if (!header) return null;
  const m = header.match(/^Bearer\s+(.+)$/i);
  if (!m) {
    res.status(401).json({ error: "Invalid Authorization header" });
    return "rejected";
  }
  const payload = await verifyToken(m[1]);
  if (!payload) {
    res.status(401).json({ error: "Invalid or expired token" });
    return "rejected";
  }
  const sub = typeof payload.sub === "string" ? payload.sub : null;
  if (!sub) {
    res.status(401).json({ error: "Invalid token" });
    return "rejected";
  }
  const email = typeof payload.email === "string" ? payload.email : undefined;
  return { id: sub, email };
}

async function verifyToken(token: string) {
  try {
    const { payload } = await jwtVerify(token, JWKS);
    return payload;
  } catch {
    return null;
  }
}

/**
 * Per-endpoint rate limiters backed by Upstash Redis. The previous
 * implementation was an in-memory token bucket that reset on every Vercel
 * cold start and didn't share state between concurrent serverless instances —
 * fine for a handful of beta testers, not safe for public Replicate spend.
 *
 * Each limiter has its own prefix so independent abuse surfaces don't share
 * a budget (the cutout limiter shouldn't lock out a user's magic-link send
 * and vice versa).
 *
 * If Upstash is misconfigured or temporarily unreachable we fail OPEN — better
 * to serve a request than to lock everyone out. The error is logged so it's
 * visible in Vercel logs.
 */
const upstashRedis: Redis | null = (() => {
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) {
    console.warn("Upstash env vars missing — rate limiters disabled");
    return null;
  }
  return new Redis({ url, token });
})();

function makeLimiter(prefix: string, limiter: Ratelimit["limiter"]): Ratelimit | null {
  if (!upstashRedis) return null;
  return new Ratelimit({
    redis: upstashRedis,
    limiter,
    analytics: false,
    prefix,
  });
}

// Cutout: token bucket capacity 3, refills 3 tokens / 6 s. Preserved for
// existing callers (`/v1/cutout`, `/v1/colorize`, `/v1/fill-body`).
const cutoutLimiter = makeLimiter("ratelimit:cutout", Ratelimit.tokenBucket(3, "6 s", 3));

// Magic-link: sliding window, 3 sends/min and 10/hour per fingerprint.
// Tight enough to deter SMTP abuse + targeted spam, loose enough to absorb
// user retries when they click the in-app "Resend" button impatiently.
const magicLinkFingerprintMinuteLimiter = makeLimiter(
  "ratelimit:magic-link:fp:min",
  Ratelimit.slidingWindow(3, "60 s"),
);
const magicLinkFingerprintHourLimiter = makeLimiter(
  "ratelimit:magic-link:fp:hr",
  Ratelimit.slidingWindow(10, "1 h"),
);

// Anonymous /v1/account lookups (fingerprint enumeration defence). Keyed
// by IP so an attacker can't iterate UUIDs from a single host without
// hitting the limit. Generous enough that legitimate clients polling on
// app launch + window focus don't trip it.
const anonAccountLimiter = makeLimiter(
  "ratelimit:anon-account",
  Ratelimit.slidingWindow(60, "60 s"),
);

// Anonymous checkout (Stripe API abuse defence). Pre-auth checkout creates
// a Stripe Session and a customer; even cancelled sessions consume API
// quota and pollute the dashboard. 5/hour per IP is well above any honest
// flow.
const anonCheckoutLimiter = makeLimiter(
  "ratelimit:anon-checkout",
  Ratelimit.slidingWindow(5, "1 h"),
);

// Circuit-breaker state (audit MEDIUM #20). The limiters fail OPEN on
// Upstash errors so an outage doesn't lock everyone out — but a steady
// stream of Upstash errors then means EVERY request bypasses the limit,
// silently turning off our abuse protection. The breaker watches
// consecutive error counts: after N errors in quick succession we stop
// calling Upstash for `coolDownMs` and treat ALL requests as
// rate-limit-passed via the existing fail-open path. The break is
// announced loudly so an on-call sees the outage in `vercel logs`
// instead of having to deduce it from missing rate-limit signal.
//
// State is module-local (one breaker per warm function instance). Fluid
// Compute reuses instances; cold starts reset the breaker, which is
// fine — a fresh instance gets one more chance to reach Upstash.
const BREAKER_ERROR_THRESHOLD = 5;
const BREAKER_COOLDOWN_MS = 60_000;

const breaker = {
  consecutiveErrors: 0,
  openedAt: 0,
};

function breakerIsOpen(): boolean {
  if (breaker.openedAt === 0) return false;
  if (Date.now() - breaker.openedAt > BREAKER_COOLDOWN_MS) {
    // Cool-down elapsed — half-open: let the next request through to
    // probe Upstash. A successful call resets the breaker; a failure
    // re-opens it for another cooldown.
    breaker.openedAt = 0;
    breaker.consecutiveErrors = 0;
    return false;
  }
  return true;
}

function recordBreakerSuccess(): void {
  breaker.consecutiveErrors = 0;
  breaker.openedAt = 0;
}

function recordBreakerError(): void {
  breaker.consecutiveErrors += 1;
  if (breaker.consecutiveErrors >= BREAKER_ERROR_THRESHOLD && breaker.openedAt === 0) {
    breaker.openedAt = Date.now();
    console.error(
      `[ratelimit-breaker] Upstash failed ${breaker.consecutiveErrors} consecutive times — ` +
      `failing open for ${BREAKER_COOLDOWN_MS / 1000}s. Rate limits are NOT being enforced.`,
    );
  }
}

async function tryLimit(limiter: Ratelimit | null, key: string): Promise<boolean> {
  if (!limiter) return true;
  if (breakerIsOpen()) return true;
  try {
    const { success } = await limiter.limit(key);
    recordBreakerSuccess();
    return success;
  } catch (err) {
    recordBreakerError();
    // First few errors still get logged so a brief Upstash blip is
    // visible. Once the breaker opens, recordBreakerError logs once at
    // the threshold; further calls within the cooldown short-circuit
    // before reaching this catch.
    console.error("Rate limiter error — failing open", err);
    return true;
  }
}

export async function checkRateLimit(userId: string): Promise<boolean> {
  return tryLimit(cutoutLimiter, userId);
}

/**
 * Per-fingerprint magic-link send limit. Both windows must pass: the per-
 * minute cap stops bursts, the per-hour cap stops slow drips.
 */
export async function checkMagicLinkRateLimit(fingerprint: string): Promise<boolean> {
  const [minuteOk, hourOk] = await Promise.all([
    tryLimit(magicLinkFingerprintMinuteLimiter, fingerprint),
    tryLimit(magicLinkFingerprintHourLimiter, fingerprint),
  ]);
  return minuteOk && hourOk;
}

export async function checkAnonAccountRateLimit(ip: string): Promise<boolean> {
  return tryLimit(anonAccountLimiter, ip);
}

export async function checkAnonCheckoutRateLimit(ip: string): Promise<boolean> {
  return tryLimit(anonCheckoutLimiter, ip);
}

/**
 * True when the caller's e-mail is on the DEV_UNLIMITED_EMAILS allowlist
 * (comma-separated env var). Dev-allowlisted users skip credit/trial gates
 * and may use the `model_override` parameter (E01.10). Canonical home of
 * the gate — /v1/account and /v1/checkout/topup still carry local copies
 * from before E01.10; route new callers here.
 */
export function isDevUnlimitedUser(email: string | null | undefined): boolean {
  if (!email) return false;
  const list = (process.env.DEV_UNLIMITED_EMAILS ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  return list.includes(email.toLowerCase());
}

/**
 * Extract the originating client IP. Vercel terminates TLS at the edge and
 * forwards the real client address in `x-forwarded-for` (first hop). Falls
 * back to the socket address if the header is missing (e.g. local
 * `vercel dev`). Returns `"unknown"` so the limiter key is never empty —
 * empty keys would collapse all anonymous traffic into one bucket.
 */
export function clientIp(req: VercelRequest): string {
  const fwd = req.headers["x-forwarded-for"];
  const raw = Array.isArray(fwd) ? fwd[0] : fwd;
  if (typeof raw === "string" && raw.length > 0) {
    const first = raw.split(",")[0]?.trim();
    if (first) return first;
  }
  const sock = req.socket?.remoteAddress;
  if (typeof sock === "string" && sock.length > 0) return sock;
  return "unknown";
}

/**
 * Validate and normalise the `X-Device-Fingerprint` header. The macOS client
 * generates the value via `UUID().uuidString`, so we accept exactly that
 * shape (8-4-4-4-12 hex, case-insensitive). Rejects malformed values with
 * 400 before any DB / Stripe / SMTP work happens — every anonymous endpoint
 * that trusted this header previously was vulnerable to enumeration via
 * crafted strings.
 *
 * Returns the lowercased UUID on success, or `null` after writing the 400.
 */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function requireDeviceFingerprint(
  req: VercelRequest,
  res: VercelResponse,
): string | null {
  const value = readDeviceFingerprint(req);
  if (!value) {
    res.status(400).json({ error: "missing_device_fingerprint" });
    return null;
  }
  return value;
}

/**
 * Non-throwing variant for endpoints where a missing/malformed fingerprint
 * is a soft signal (e.g. /v1/account, which falls through to the free-tier
 * response). Returns the lowercased UUID or `null` — never writes a 400.
 */
export function readDeviceFingerprint(req: VercelRequest): string | null {
  const raw = req.headers["x-device-fingerprint"];
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (typeof value !== "string" || !UUID_RE.test(value)) return null;
  return value.toLowerCase();
}

/**
 * Mask an email for anonymous-context responses. The macOS app needs to
 * confirm "we sent to <address>" without the backend echoing the full
 * address to whoever holds the device fingerprint — that would turn the
 * anonymous endpoints into a fingerprint-to-email lookup oracle. Keeps
 * the first and last character of the local part and the first character
 * of the domain so the user can still recognise their own address.
 *
 * Examples:  thierry@example.com → t****y@e******.com
 *            ab@x.io             → a*b@x***.io
 *            a@b.io              → a@b**.io
 */
export function maskEmail(email: string | null | undefined): string | null {
  if (!email) return null;
  const at = email.indexOf("@");
  if (at <= 0 || at === email.length - 1) return null;
  const local = email.slice(0, at);
  const domain = email.slice(at + 1);
  const dot = domain.lastIndexOf(".");
  const tld = dot > 0 ? domain.slice(dot) : "";
  const domainHead = dot > 0 ? domain.slice(0, dot) : domain;

  const maskedLocal = local.length === 1
    ? local
    : local.length === 2
      ? `${local[0]}*${local[1]}`
      : `${local[0]}${"*".repeat(Math.max(1, local.length - 2))}${local.slice(-1)}`;
  const maskedDomain = domainHead.length === 1
    ? `${domainHead}**`
    : `${domainHead[0]}${"*".repeat(Math.max(1, domainHead.length - 1))}`;
  return `${maskedLocal}@${maskedDomain}${tld}`;
}
