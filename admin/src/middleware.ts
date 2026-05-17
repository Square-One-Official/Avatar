import { NextResponse, type NextRequest } from "next/server";
import { mfaCookieName, verifyMfaCookie } from "./lib/mfa";
import {
  checkApiRateLimit,
  checkNewsletterRateLimit,
  clientIp,
} from "./lib/ratelimit";

/**
 * Gates the Payload admin UI + REST API behind a TOTP-verified cookie
 * (audit HIGH #11). The browser flow becomes:
 *
 *     GET /admin/*           → no mfa cookie → redirect /mfa
 *     POST /api/mfa/verify   → check TOTP, set mfa cookie
 *     GET /admin/*           → cookie valid → Payload's password login
 *
 * Machine-to-machine traffic (the backend at api.aaavatar.nl using the
 * Payload API key) is exempt: an `Authorization: users API-Key …` header
 * is itself a separately-managed secret and Payload still authenticates
 * the request. Adding TOTP on top would just block the integration with
 * no security gain.
 *
 * The `/mfa` page and `/api/mfa/*` endpoints are deliberately not gated
 * so the user can reach them while unauthenticated. Static assets
 * (`_next/static/*`) and the `favicon` are excluded via the matcher
 * config so we don't pay HMAC cost on every served chunk.
 */
export async function middleware(req: NextRequest): Promise<NextResponse> {
  const { pathname } = req.nextUrl;

  // Allow the MFA gateway routes themselves through unconditionally.
  if (
    pathname === "/mfa" ||
    pathname.startsWith("/mfa/") ||
    pathname.startsWith("/api/mfa/")
  ) {
    return NextResponse.next();
  }

  // Rate limit every `/api/*` request before authn (audit MEDIUM #22).
  // Doing it up-front means a stuck script bouncing off 401s also gets
  // bucketed — the limiter sees attempted abuse even when authn fails.
  // Static admin shell assets and `/mfa/*` are excluded above.
  if (pathname.startsWith("/api/")) {
    const ip = clientIp(req.headers);
    const apiOk = await checkApiRateLimit(ip);
    if (!apiOk) {
      return NextResponse.json({ error: "rate_limited" }, { status: 429 });
    }
    // Newsletter blast is gated more tightly because every call sends
    // real emails through Resend. Layered on top of the general cap —
    // both must pass.
    if (pathname.startsWith("/api/send-newsletter")) {
      const newsletterOk = await checkNewsletterRateLimit(ip);
      if (!newsletterOk) {
        return NextResponse.json({ error: "rate_limited" }, { status: 429 });
      }
    }
  }

  // Skip the MFA gate for backend API-key traffic. Payload's own auth
  // checks the key; this short-circuit only decides whether to enforce
  // TOTP. Rate-limiting above already applied to these requests too.
  const auth = req.headers.get("authorization") ?? "";
  if (/^users\s+API-Key\s+/i.test(auth)) {
    return NextResponse.next();
  }

  const cookie = req.cookies.get(mfaCookieName)?.value;
  const ok = await verifyMfaCookie(cookie);
  if (ok) {
    return NextResponse.next();
  }

  // /api/* without MFA gets a 401 so any fetch from the unauthenticated
  // admin shell surfaces the failure clearly; /admin/* gets a redirect so
  // the operator lands on the TOTP form.
  if (pathname.startsWith("/api/")) {
    return NextResponse.json({ error: "mfa_required" }, { status: 401 });
  }
  const url = req.nextUrl.clone();
  url.pathname = "/mfa";
  url.search = "";
  // Capture the original destination so successful verification can bounce
  // the user back where they were headed.
  if (pathname !== "/" && pathname !== "/mfa") {
    url.searchParams.set("next", pathname);
  }
  return NextResponse.redirect(url);
}

export const config = {
  matcher: [
    "/admin/:path*",
    "/api/:path*",
  ],
};
