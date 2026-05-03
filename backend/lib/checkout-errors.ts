import type { VercelRequest, VercelResponse } from "@vercel/node";

/**
 * Shared error responder for `/v1/checkout/*` endpoints.
 *
 * Goals:
 * - Always log the full error server-side (Vercel runtime logs) so we can
 *   trace what Stripe / Supabase actually returned. Stripe errors get their
 *   most useful fields (`type`, `code`, `param`, `message`, `requestId`)
 *   pulled out so they're greppable without expanding the stack.
 * - Never leak the raw error payload to the client. Return a stable code
 *   the macOS app maps to localized copy, plus a `requestId` so support can
 *   cross-reference what the user saw with the server log.
 * - Distinguish *Stripe is unavailable / misconfigured* from generic
 *   *we couldn't init checkout* — different copy on the client.
 */
export function sendCheckoutError(
  req: VercelRequest,
  res: VercelResponse,
  endpoint: string,
  err: unknown,
): void {
  const headerId = req.headers["x-vercel-id"];
  const requestId = typeof headerId === "string" ? headerId : cryptoRandomId();

  const stripeFields = extractStripeFields(err);
  const isStripe = stripeFields !== null;

  console.error(`${endpoint} error`, {
    requestId,
    stripe: stripeFields,
    error: err,
  });

  res.status(502).json({
    error: isStripe ? "stripe_unavailable" : "checkout_init_failed",
    requestId,
  });
}

type StripeErrorShape = {
  type?: string;
  code?: string;
  param?: string;
  message?: string;
  requestId?: string;
};

function extractStripeFields(err: unknown): StripeErrorShape | null {
  if (!err || typeof err !== "object") return null;
  const e = err as Record<string, unknown>;
  const type = typeof e.type === "string" ? e.type : undefined;
  if (!type || !type.startsWith("Stripe")) return null;
  return {
    type,
    code: typeof e.code === "string" ? e.code : undefined,
    param: typeof e.param === "string" ? e.param : undefined,
    message: typeof e.message === "string" ? e.message : undefined,
    requestId: typeof e.requestId === "string" ? e.requestId : undefined,
  };
}

function cryptoRandomId(): string {
  // Vercel's Node runtime exposes globalThis.crypto since 18.x.
  const c = (globalThis as { crypto?: { randomUUID?: () => string } }).crypto;
  return c?.randomUUID ? c.randomUUID() : `r_${Date.now()}_${Math.random().toString(36).slice(2)}`;
}
