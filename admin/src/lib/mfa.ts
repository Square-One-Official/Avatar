import { TOTP, Secret } from "otpauth";

/**
 * Admin TOTP gate (audit HIGH #11). The admin app sits at admin.aaavatar.nl
 * behind Payload's password login; this module adds a TOTP step before the
 * browser ever sees the Payload admin shell, turning the single-factor
 * password-only login into real 2FA without requiring a Payload v3 plugin.
 *
 * Design notes:
 *   - One shared TOTP secret (`ADMIN_TOTP_SECRET`) provisioned out-of-band
 *     in Vercel. The admin set is tiny (one operator at the moment) so we
 *     don't need per-user secrets stored in Postgres. When a second admin
 *     is added, this scales by switching to a `users.mfaSecret` column +
 *     per-user verification.
 *   - The "did the browser already pass TOTP" signal is a separate signed
 *     cookie (`mfa-session`), independent of Payload's session cookie.
 *     Logging out of Payload doesn't drop the MFA cookie and vice versa —
 *     the two factors are decoupled by design (each can be revoked
 *     individually).
 *   - Cookie is signed via Web Crypto HMAC-SHA256 so the middleware can
 *     verify in the Edge runtime without pulling in a JWT library.
 *
 * Machine-to-machine traffic (the backend at api.aaavatar.nl hitting
 * Payload's REST API with `Authorization: users API-Key …`) is exempt
 * from the TOTP gate — see the middleware. API keys are themselves a
 * secret and adding TOTP on top would defeat the M2M use case.
 */

const COOKIE_NAME = "mfa-session";
const COOKIE_TTL_SECONDS = 8 * 60 * 60; // 8 hours, matches Payload tokenExpiration

export interface MfaCookiePayload {
  /** ISO timestamp the cookie was issued. */
  iat: string;
  /** Unix epoch seconds the cookie expires. */
  exp: number;
  /** Random nonce so two cookies issued in the same second never collide. */
  nonce: string;
}

export const mfaCookieName = COOKIE_NAME;
export const mfaCookieTtlSeconds = COOKIE_TTL_SECONDS;

/**
 * Build a TOTP verifier configured the way every TOTP authenticator app
 * defaults to (SHA-1, 6 digits, 30-second window). The secret is the
 * base32 string the operator scans into their authenticator app.
 */
function buildTotp(): TOTP {
  const secret = process.env.ADMIN_TOTP_SECRET;
  if (!secret) {
    throw new Error("ADMIN_TOTP_SECRET is not configured");
  }
  return new TOTP({
    issuer: "Aaavatar Admin",
    label: "admin",
    algorithm: "SHA1",
    digits: 6,
    period: 30,
    secret: Secret.fromBase32(secret),
  });
}

/**
 * Verifies a 6-digit TOTP code. Accepts a ±1 step window so a code typed
 * across a 30-second boundary still works. Returns true on success.
 */
export function verifyTotpCode(code: string): boolean {
  const normalised = code.replace(/\s+/g, "");
  if (!/^\d{6}$/.test(normalised)) return false;
  const totp = buildTotp();
  const delta = totp.validate({ token: normalised, window: 1 });
  return delta !== null;
}

// MARK: Signed-cookie helpers (HMAC-SHA256 via Web Crypto)

async function importSigningKey(): Promise<CryptoKey> {
  const secret = process.env.ADMIN_MFA_SIGNING_SECRET;
  if (!secret) {
    throw new Error("ADMIN_MFA_SIGNING_SECRET is not configured");
  }
  const raw = new TextEncoder().encode(secret);
  return crypto.subtle.importKey(
    "raw",
    raw,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

function base64UrlEncode(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let str = "";
  for (let i = 0; i < view.length; i++) str += String.fromCharCode(view[i]);
  return btoa(str).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function base64UrlDecode(s: string): Uint8Array {
  const padded = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  const bin = atob(padded);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/**
 * Mints a signed cookie value asserting the holder passed TOTP. Format
 * `<base64url(payload)>.<base64url(hmac)>` so middleware can verify it
 * with a single Web Crypto call. The HMAC binds the expiry to the
 * server's signing key — flipping the `exp` byte invalidates the
 * signature.
 */
export async function issueMfaCookie(): Promise<string> {
  const payload: MfaCookiePayload = {
    iat: new Date().toISOString(),
    exp: Math.floor(Date.now() / 1000) + COOKIE_TTL_SECONDS,
    nonce: base64UrlEncode(crypto.getRandomValues(new Uint8Array(12))),
  };
  const json = JSON.stringify(payload);
  const body = base64UrlEncode(new TextEncoder().encode(json));
  const key = await importSigningKey();
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return `${body}.${base64UrlEncode(sig)}`;
}

/**
 * Returns true iff `value` is a valid, non-expired MFA cookie. Safe to
 * call from middleware on every request — does no DB work. Web Crypto's
 * `verify` is constant-time over the signature comparison.
 */
export async function verifyMfaCookie(value: string | undefined): Promise<boolean> {
  if (typeof value !== "string") return false;
  const parts = value.split(".");
  if (parts.length !== 2) return false;
  const [body, sigB64] = parts;
  try {
    const key = await importSigningKey();
    // Cast through `BufferSource` — newer TS dom lib distinguishes
    // `Uint8Array<ArrayBufferLike>` from `Uint8Array<ArrayBuffer>` and
    // Web Crypto's overloads only accept the latter. Runtime is identical.
    const sigBytes = base64UrlDecode(sigB64) as unknown as BufferSource;
    const bodyBytes = new TextEncoder().encode(body) as unknown as BufferSource;
    const valid = await crypto.subtle.verify("HMAC", key, sigBytes, bodyBytes);
    if (!valid) return false;
    const json = new TextDecoder().decode(base64UrlDecode(body));
    const payload = JSON.parse(json) as MfaCookiePayload;
    if (typeof payload.exp !== "number") return false;
    if (payload.exp < Math.floor(Date.now() / 1000)) return false;
    return true;
  } catch {
    return false;
  }
}
