import type { VercelRequest, VercelResponse } from "@vercel/node";
import {
  checkAnonAccountRateLimit,
  checkMagicLinkRateLimit,
  clientIp,
} from "../../../lib/auth.js";
import { findUserIdByEmail, supabase } from "../../../lib/supabase.js";

const APP_SCHEME = process.env.APP_URL_SCHEME ?? "aaavatar";
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * POST /v1/auth/send-recovery-email
 *
 * Triggered by the "Already paid? Restore Pro with email" affordance on
 * the welcome / onboarding sign-in surfaces. Lets a user on a fresh
 * install (or a brand-new Mac) recover their Pro entitlement using only
 * the email they paid Stripe with — no Google account required.
 *
 * Distinct from `/v1/account/resend-magic-link`:
 *   - This endpoint accepts an arbitrary email in the body (there's no
 *     device_grants row yet on a fresh install, so we can't identify the
 *     account by fingerprint).
 *   - To avoid turning the endpoint into an account-existence oracle, the
 *     response is identical whether or not the email matches a user.
 *     Rate limits are applied BEFORE the user lookup so a probing attacker
 *     burns the same budget either way.
 *
 * Anti-abuse:
 *   - Email-shape validation up front.
 *   - Per-email + per-IP rate limit (see `checkRecoveryEmailRateLimit`).
 *   - `shouldCreateUser: false` — never auto-creates accounts from this
 *     endpoint; new accounts come from Stripe checkout, period.
 *
 * Returns:
 *   200 { sent: true }                          — always, on any well-formed call
 *   400 { error: "invalid_email" }
 *   405 { error: "method_not_allowed" }
 *   429 { error: "rate_limited" }
 *
 * The 200 response is intentionally information-light. The client shows
 * "If we have an account for that email, we sent a sign-in link." — no
 * confirmation that the email exists in our system.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const body = (req.body ?? {}) as { email?: unknown };
  const rawEmail = typeof body.email === "string" ? body.email.trim() : "";
  if (!rawEmail || !EMAIL_RE.test(rawEmail) || rawEmail.length > 254) {
    res.status(400).json({ error: "invalid_email" });
    return;
  }
  const email = rawEmail.toLowerCase();

  // Rate-limit before the user lookup. Reuse the existing limiters so we
  // don't fork a third buckets schema: per-email reuses the magic-link
  // limiter (the function takes any string, the semantics are identical
  // — bound how often a given inbox can receive a magic link). Per-IP
  // reuses the anon-account limiter (the right defensive shape for
  // anonymous endpoints; defends against attackers iterating addresses
  // from one host).
  //
  // Both must pass; failures return the same 429 regardless of whether
  // the email exists. This is load-bearing for the anti-enumeration story
  // — the alternative (look up first, then maybe rate-limit) would let a
  // probing attacker tell existing emails from missing ones by timing.
  const [emailOk, ipOk] = await Promise.all([
    checkMagicLinkRateLimit(email),
    checkAnonAccountRateLimit(clientIp(req)),
  ]);
  if (!emailOk || !ipOk) {
    res.status(429).json({ error: "rate_limited" });
    return;
  }

  try {
    const userId = await findUserIdByEmail(email);
    if (!userId) {
      // No account for this address. Return the generic 200 so the caller
      // can't distinguish "no such user" from "link sent". The rate limit
      // has already debited this email's bucket, so probing is bounded.
      res.status(200).json({ sent: true });
      return;
    }

    // signInWithOtp uses Supabase's templated magic-link email. The user
    // was created by Stripe webhook with email_confirm: true, so
    // shouldCreateUser: false is safe and means this endpoint can never
    // accidentally create an account.
    const { error: sendErr } = await supabase.auth.signInWithOtp({
      email,
      options: {
        shouldCreateUser: false,
        emailRedirectTo: `${APP_SCHEME}://auth-callback`,
      },
    });
    if (sendErr) {
      // Don't leak the failure to the client — surface a generic 200 so
      // the endpoint stays oracle-resistant. The error is still logged
      // so an operator can diagnose SMTP issues.
      console.error("/v1/auth/send-recovery-email send failed", sendErr);
    }
    res.status(200).json({ sent: true });
  } catch (err) {
    console.error("/v1/auth/send-recovery-email error", err);
    // Same generic 200 — masking errors costs us a clearer client UX
    // but preserves the no-enumeration guarantee.
    res.status(200).json({ sent: true });
  }
}
