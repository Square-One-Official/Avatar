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
 * Per-user rate limiter backed by Upstash Redis. The previous implementation
 * was an in-memory token bucket that reset on every Vercel cold start and
 * didn't share state between concurrent serverless instances — fine for a
 * handful of beta testers, not safe for public Replicate spend.
 *
 * Token-bucket semantics: capacity 3, refills at 0.5 tokens/sec (~1 request
 * per 2 seconds sustained, with a 3-request burst). Matches the limits the
 * old implementation advertised.
 *
 * If Upstash is misconfigured or temporarily unreachable we fail OPEN — better
 * to serve a request than to lock everyone out. The error is logged so it's
 * visible in Vercel logs.
 */
const ratelimit: Ratelimit | null = (() => {
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) {
    console.warn("Upstash env vars missing — rate limiter disabled");
    return null;
  }
  return new Ratelimit({
    redis: new Redis({ url, token }),
    limiter: Ratelimit.tokenBucket(3, "6 s", 3),
    analytics: false,
    prefix: "ratelimit:cutout",
  });
})();

export async function checkRateLimit(userId: string): Promise<boolean> {
  if (!ratelimit) return true;
  try {
    const { success } = await ratelimit.limit(userId);
    return success;
  } catch (err) {
    console.error("Rate limiter error — failing open", err);
    return true;
  }
}
