import { createHmac } from "node:crypto";

/**
 * Admin-side signer for newsletter unsubscribe links (audit HIGH #15).
 * Mirrors the verifier in `backend/lib/unsubscribe-token.ts` byte-for-byte
 * — the two files MUST stay in sync. The signing key is shared via the
 * `UNSUBSCRIBE_SIGNING_SECRET` env var set on both Vercel projects.
 *
 * Format: `<base64url(payload)>.<base64url(hmac-sha256)>`
 *   payload = JSON({ e: email, i: issuedAt-unix-seconds })
 *   hmac    = HMAC-SHA256(payload, UNSUBSCRIBE_SIGNING_SECRET)
 */

function base64UrlEncode(buf: Buffer): string {
  return buf.toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

export function signUnsubscribeToken(email: string): string {
  const secret = process.env.UNSUBSCRIBE_SIGNING_SECRET;
  if (!secret) throw new Error("UNSUBSCRIBE_SIGNING_SECRET is not configured");
  const payload = {
    e: email.trim().toLowerCase(),
    i: Math.floor(Date.now() / 1000),
  };
  const body = base64UrlEncode(Buffer.from(JSON.stringify(payload)));
  const sig = createHmac("sha256", secret).update(body).digest();
  return `${body}.${base64UrlEncode(sig)}`;
}

/**
 * Public URL the macOS-app newsletter footer links to. Reads
 * `UNSUBSCRIBE_BASE_URL` so preview deploys can target a non-prod backend
 * without code changes; falls back to the live api host.
 */
export function unsubscribeUrlFor(email: string): string {
  const base = (process.env.UNSUBSCRIBE_BASE_URL ?? "https://api.aaavatar.nl").replace(/\/$/, "");
  const token = signUnsubscribeToken(email);
  return `${base}/v1/unsubscribe?token=${encodeURIComponent(token)}`;
}
