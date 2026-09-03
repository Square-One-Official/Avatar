import { createHmac } from "node:crypto";

/**
 * Admin-side signer voor newsletter double-opt-in confirm-links (E17.6).
 * Spiegelt `unsubscribe-token.ts` byte-voor-byte met de verifier in
 * `backend/lib/optin-token.ts` — die twee MOETEN in sync blijven. Sleutel
 * via `OPTIN_SIGNING_SECRET` (gedeeld op beide Vercel-projecten); valt terug
 * op `UNSUBSCRIBE_SIGNING_SECRET` zodat één secret kan volstaan.
 *
 * Format: `<base64url(payload)>.<base64url(hmac-sha256)>`
 *   payload = JSON({ e: email, i: issuedAt-unix-seconds })
 */
function base64UrlEncode(buf: Buffer): string {
  return buf.toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function secret(): string {
  const s = process.env.OPTIN_SIGNING_SECRET ?? process.env.UNSUBSCRIBE_SIGNING_SECRET;
  if (!s) throw new Error("OPTIN_SIGNING_SECRET / UNSUBSCRIBE_SIGNING_SECRET is not configured");
  return s;
}

export function signOptInToken(email: string): string {
  const payload = { e: email.trim().toLowerCase(), i: Math.floor(Date.now() / 1000) };
  const bodyStr = base64UrlEncode(Buffer.from(JSON.stringify(payload)));
  const sig = createHmac("sha256", secret()).update(bodyStr).digest();
  return `${bodyStr}.${base64UrlEncode(sig)}`;
}

/** Publieke confirm-URL voor de double-opt-in mail. */
export function confirmUrlFor(email: string): string {
  const base = (process.env.OPTIN_BASE_URL ?? "https://api.aaavatar.nl").replace(/\/$/, "");
  return `${base}/v1/newsletter/confirm?token=${encodeURIComponent(signOptInToken(email))}`;
}
