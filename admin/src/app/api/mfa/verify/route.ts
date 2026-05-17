import { NextResponse } from "next/server";
import {
  issueMfaCookie,
  mfaCookieName,
  mfaCookieTtlSeconds,
  verifyTotpCode,
} from "../../../../lib/mfa";

/**
 * POST /api/mfa/verify — accept a 6-digit TOTP code, set the MFA session
 * cookie on success. The middleware exempts this route so unauthenticated
 * browsers can reach it; everything else under `/api` requires a valid
 * MFA cookie.
 *
 * The body is intentionally minimal (`{ code: string }`) and the response
 * shape is `{ ok: true }` / `{ error }` — easy to fetch from the small
 * /mfa page client.
 */
export async function POST(req: Request): Promise<NextResponse> {
  let body: { code?: unknown };
  try {
    body = (await req.json()) as { code?: unknown };
  } catch {
    return NextResponse.json({ error: "invalid_body" }, { status: 400 });
  }
  const code = typeof body.code === "string" ? body.code : "";

  let valid = false;
  try {
    valid = verifyTotpCode(code);
  } catch (err) {
    // Configuration error (missing ADMIN_TOTP_SECRET / signing key). Log
    // server-side so the operator sees the cause in Vercel logs; surface
    // a generic 500 to avoid leaking which env var is missing.
    console.error("/api/mfa/verify config error", err);
    return NextResponse.json({ error: "server_misconfigured" }, { status: 500 });
  }
  if (!valid) {
    return NextResponse.json({ error: "invalid_code" }, { status: 401 });
  }

  const cookie = await issueMfaCookie();
  const res = NextResponse.json({ ok: true });
  res.cookies.set({
    name: mfaCookieName,
    value: cookie,
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    path: "/",
    maxAge: mfaCookieTtlSeconds,
  });
  return res;
}
