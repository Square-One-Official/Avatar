import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

/**
 * Per-endpoint rate limiters for the admin Next.js app (audit MEDIUM #22).
 * Plumbed into `src/middleware.ts` after the MFA gate so:
 *
 *   - Any `/api/*` request (browser via MFA cookie, OR the backend
 *     authenticated by API key) is metered with a generous `apiLimiter`
 *     so a stuck script can't fan out into Payload / Postgres.
 *   - The newsletter blast endpoint (`/api/send-newsletter`) has its own
 *     stricter `newsletterLimiter` because a single call sends real
 *     emails through Resend — abuse there has measurable cost and bad
 *     deliverability consequences.
 *
 * Mirrors the design in `backend/lib/auth.ts`: one Redis client, multiple
 * prefixed limiters, fail-open on Upstash outage with a logged warning so
 * an Upstash incident doesn't lock out the operator.
 */

const redis: Redis | null = (() => {
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) {
    console.warn("Upstash env vars missing — admin rate limiters disabled");
    return null;
  }
  return new Redis({ url, token });
})();

function make(prefix: string, limiter: Ratelimit["limiter"]): Ratelimit | null {
  if (!redis) return null;
  return new Ratelimit({ redis, limiter, analytics: false, prefix });
}

// Generic Payload + custom-endpoint cap. 120/min/IP is well above what
// either the operator clicking through the admin or the avatars-api
// backend polling for announcements needs (the backend caches for 60 s),
// but tight enough that a runaway script trips the limiter long before
// it can do real damage.
const apiLimiter = make(
  "ratelimit:admin-api",
  Ratelimit.slidingWindow(120, "60 s"),
);

// Newsletter blast: 5/hour/IP. Each call kicks off a real Resend send,
// so this needs to fail-closed against accidental double-clicks and
// against credential theft (a stolen API key can blast every account
// before we revoke).
const newsletterLimiter = make(
  "ratelimit:admin-newsletter",
  Ratelimit.slidingWindow(5, "1 h"),
);

async function tryLimit(limiter: Ratelimit | null, key: string): Promise<boolean> {
  if (!limiter) return true;
  try {
    const { success } = await limiter.limit(key);
    return success;
  } catch (err) {
    console.error("admin rate-limiter error — failing open", err);
    return true;
  }
}

export async function checkApiRateLimit(key: string): Promise<boolean> {
  return tryLimit(apiLimiter, key);
}

export async function checkNewsletterRateLimit(key: string): Promise<boolean> {
  return tryLimit(newsletterLimiter, key);
}

/**
 * Extract the originating client IP from a Next.js middleware request.
 * Falls back to `"unknown"` so the limiter key is never empty (an empty
 * key would collapse all unauth'd traffic into a single bucket).
 */
export function clientIp(headers: Headers): string {
  const fwd = headers.get("x-forwarded-for");
  if (fwd) {
    const first = fwd.split(",")[0]?.trim();
    if (first) return first;
  }
  const real = headers.get("x-real-ip");
  if (real && real.trim()) return real.trim();
  return "unknown";
}
