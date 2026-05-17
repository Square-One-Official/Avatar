#!/usr/bin/env node
// One-off helper: generates a fresh TOTP secret + signing key for the
// admin MFA gate (audit HIGH #11). Run once, paste the values into the
// Vercel `avatar-admin` project env (Production + Preview), and scan the
// printed otpauth:// URI into your authenticator app.
//
// Usage:  node scripts/setup-mfa.mjs
//
// Outputs (to stdout):
//   ADMIN_TOTP_SECRET          — paste into Vercel env
//   ADMIN_MFA_SIGNING_SECRET   — paste into Vercel env (HMAC key for cookies)
//   otpauth://...              — scan / paste into 1Password / Authy / etc.
//
// No deps beyond `otpauth` (already in package.json).

import { Secret, TOTP } from "otpauth";
import { randomBytes } from "node:crypto";

const totpSecret = new Secret({ size: 32 });
const totp = new TOTP({
  issuer: "Aaavatar Admin",
  label: "admin",
  algorithm: "SHA1",
  digits: 6,
  period: 30,
  secret: totpSecret,
});

// 64 random bytes, base64url. The middleware HMACs the cookie payload
// with this key — any value with at least ~256 bits of entropy is fine;
// we go double for headroom.
const signingSecret = randomBytes(64).toString("base64url");

console.log("");
console.log("Add the following to the avatar-admin Vercel project");
console.log("(Production + Preview), then redeploy:");
console.log("");
console.log(`  ADMIN_TOTP_SECRET=${totpSecret.base32}`);
console.log(`  ADMIN_MFA_SIGNING_SECRET=${signingSecret}`);
console.log("");
console.log("Scan this URI (or paste it into 1Password / Authy / etc.):");
console.log("");
console.log(`  ${totp.toString()}`);
console.log("");
console.log("Or enter the secret manually with these settings:");
console.log("  Type:      Time-based (TOTP)");
console.log("  Algorithm: SHA-1");
console.log("  Digits:    6");
console.log("  Period:    30 seconds");
console.log(`  Secret:    ${totpSecret.base32}`);
console.log("");
