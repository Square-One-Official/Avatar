import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * Signed unsubscribe-link tokens (audit HIGH #15 — GDPR Art. 21 / CAN-SPAM
 * one-click unsubscribe). Both the admin (signs at newsletter send time)
 * and the backend (verifies when the user clicks) use this module via
 * file-local copies in their respective `src/lib/` — the signing scheme
 * has to match exactly, so the shapes here and in `admin/src/lib/
 * unsubscribe-token.ts` are kept identical on purpose.
 *
 * Format: `<base64url(payload)>.<base64url(hmac-sha256)>`
 *   payload = JSON({ e: email, i: issuedAt-unix-seconds })
 *   hmac    = HMAC-SHA256(payload, UNSUBSCRIBE_SIGNING_SECRET)
 *
 * Why HMAC instead of plain JWT: keeps the dependency footprint to zero
 * (Node built-in crypto) and the wire format is short enough to fit
 * comfortably in a single mailto: link.
 */

const TOKEN_TTL_SECONDS = 365 * 24 * 60 * 60; // 1 year — unsubscribe links don't go stale

interface TokenPayload {
  /** Email the token authorises unsubscribing. Always lowercased. */
  e: string;
  /** Issued-at, unix seconds. */
  i: number;
}

function base64UrlEncode(buf: Buffer | Uint8Array): string {
  const b = Buffer.isBuffer(buf) ? buf : Buffer.from(buf);
  return b.toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function base64UrlDecode(s: string): Buffer {
  const pad = "===".slice((s.length + 3) % 4);
  return Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/") + pad, "base64");
}

function getSecret(): string {
  const secret = process.env.UNSUBSCRIBE_SIGNING_SECRET;
  if (!secret) throw new Error("UNSUBSCRIBE_SIGNING_SECRET is not configured");
  return secret;
}

export function signUnsubscribeToken(email: string): string {
  const payload: TokenPayload = {
    e: email.trim().toLowerCase(),
    i: Math.floor(Date.now() / 1000),
  };
  const body = base64UrlEncode(Buffer.from(JSON.stringify(payload)));
  const sig = createHmac("sha256", getSecret()).update(body).digest();
  return `${body}.${base64UrlEncode(sig)}`;
}

/**
 * Verify a token and return the embedded email. Returns null when the
 * signature is wrong, the payload is malformed, or the token is older
 * than the (deliberately generous) TTL.
 */
export function verifyUnsubscribeToken(token: string | undefined | null): string | null {
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
