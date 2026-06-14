import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "../../../lib/supabase.js";
import { verifyOptInToken } from "../../../lib/optin-token.js";

/**
 * GET /v1/newsletter/confirm?token=<signed-token> — double-opt-in bevestiging
 * (E17.6). De token (HMAC, 14d TTL) draagt de e-mail; bij geldigheid
 * stempelen we `newsletter_optins.confirmed_at` (idempotent) en tonen een
 * kleine bevestigingspagina. Geen auth/rate-limit: de per-e-mail-token is de
 * capability. Niet-destructief: opt-in is additief naast het bestaande
 * account-systeem; de dispatch kan optioneel op confirmed filteren (zie
 * admin/NIEUWSBRIEF-2.0.md). De `newsletter_optins`-tabel komt uit
 * backend/sql/014 (gated).
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const rawToken = req.query.token;
  const token = Array.isArray(rawToken) ? rawToken[0] : rawToken;
  const email = verifyOptInToken(token ?? null);
  if (!email) {
    sendHtml(res, 400, page("Link expired", "This confirmation link is no longer valid. Please sign up again."));
    return;
  }

  try {
    const { error } = await supabase
      .from("newsletter_optins")
      .upsert({ email, confirmed_at: new Date().toISOString() }, { onConflict: "email" });
    if (error) throw error;
  } catch (err) {
    console.error("/v1/newsletter/confirm error", err);
    sendHtml(res, 502, page("Something went wrong", "We couldn't confirm your subscription right now. Try the link again later."));
    return;
  }

  sendHtml(res, 200, page("You're subscribed ✓", "Thanks for confirming — you'll hear from Aaavatar soon."));
}

function sendHtml(res: VercelResponse, status: number, html: string) {
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.status(status).send(html);
}

function page(heading: string, body: string): string {
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${heading}</title></head><body style="font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#0B0B0D;color:#E6EAF1;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0"><div style="max-width:420px;padding:32px;text-align:center"><h1 style="font-size:22px;margin:0 0 12px;color:#fff">${heading}</h1><p style="font-size:15px;line-height:1.5;color:#C2C7D0;margin:0">${body}</p></div></body></html>`;
}
