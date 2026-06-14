import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * Newsletter double-opt-in confirm-tokens (E17.6). Verifier-helft; de signer
 * staat in `admin/src/lib/optin-token.ts` en het schema MOET identiek blijven.
 * HMAC-SHA256, zero-dependency (zoals unsubscribe-token). Sleutel via
 * `OPTIN_SIGNING_SECRET`, met fallback op `UNSUBSCRIBE_SIGNING_SECRET`.
 *
 * Format: `<base64url(payload)>.<base64url(hmac-sha256)>`
 *   payload = JSON({ e: email, i: issuedAt-unix-seconds })
 */
const TOKEN_TTL_SECONDS = 14 * 24 * 60 * 60; // 14 dagen — confirm-links vervallen

interface TokenPayload {
  e: string;
  i: number;
}

function base64UrlDecode(s: string): Buffer {
  const pad = "===".slice((s.length + 3) % 4);
  return Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/") + pad, "base64");
}

function getSecret(): string {
  const secret = process.env.OPTIN_SIGNING_SECRET ?? process.env.UNSUBSCRIBE_SIGNING_SECRET;
  if (!secret) throw new Error("OPTIN_SIGNING_SECRET / UNSUBSCRIBE_SIGNING_SECRET is not configured");
  return secret;
}

/** Verifieer een confirm-token en geef de e-mail terug, of null. */
export function verifyOptInToken(token: string | undefined | null): string | null {
  if (typeof token !== "string") return null;
  const parts = token.split(".");
  if (parts.length !== 2) return null;
  const [body, sigB64] = parts;
  try {
    const expected = createHmac("sha256", getSecret()).update(body).digest();
    const actual = base64UrlDecode(sigB64);
    if (expected.length !== actual.length) return null;
    if (!timingSafeEqual(expected, actual)) return null;
    const payload = JSON.parse(base64UrlDecode(body).toString("utf8")) as Partial<TokenPayload>;
    if (typeof payload.e !== "string" || typeof payload.i !== "number") return null;
    const ageSeconds = Math.floor(Date.now() / 1000) - payload.i;
    if (ageSeconds < 0 || ageSeconds > TOKEN_TTL_SECONDS) return null;
    return payload.e;
  } catch {
    return null;
  }
}
