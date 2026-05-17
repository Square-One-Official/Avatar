import type { VercelRequest, VercelResponse } from "@vercel/node";
import { recordNewsletterUnsubscribe } from "../../lib/payload.js";
import { verifyUnsubscribeToken } from "../../lib/unsubscribe-token.js";

/**
 * GET  /v1/unsubscribe?token=<signed-token>     — one-click via email link
 * POST /v1/unsubscribe?token=<signed-token>     — RFC 8058 List-Unsubscribe-Post
 *
 * Audit HIGH #15. The token carries the unsubscribing email + an
 * issued-at, signed with the shared `UNSUBSCRIBE_SIGNING_SECRET`. We
 * verify, record the opt-out in the Payload `newsletter-unsubscribes`
 * collection, and render a tiny HTML confirmation page (GET) or return
 * 204 (POST — mail clients want a bodyless 2xx for one-click).
 *
 * No auth header required and no rate limiter: the per-email HMAC token
 * is the capability, and the operation is idempotent (unique index in
 * Payload swallows repeats).
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "GET" && req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const rawToken = req.query.token;
  const token = Array.isArray(rawToken) ? rawToken[0] : rawToken;
  const email = verifyUnsubscribeToken(token ?? null);
  if (!email) {
    if (req.method === "POST") {
      res.status(400).json({ error: "invalid_token" });
      return;
    }
    sendHtml(res, 400, statusPage({
      heading: "Link expired",
      body: "This unsubscribe link is no longer valid. Email <a href=\"mailto:news@aaavatar.nl\">news@aaavatar.nl</a> and we'll remove you manually.",
    }));
    return;
  }

  let source: "one_click" | "list_unsubscribe_post";
  source = req.method === "POST" ? "list_unsubscribe_post" : "one_click";
  const ok = await recordNewsletterUnsubscribe(email, source);

  if (!ok) {
    if (req.method === "POST") {
      res.status(502).json({ error: "record_failed" });
      return;
    }
    sendHtml(res, 502, statusPage({
      heading: "Couldn't update your preferences right now",
      body: "We've recorded your request but the system to apply it is temporarily down. Try the link again in a few minutes, or email <a href=\"mailto:news@aaavatar.nl\">news@aaavatar.nl</a>.",
    }));
    return;
  }

  if (req.method === "POST") {
    res.status(204).end();
    return;
  }
  sendHtml(res, 200, statusPage({
    heading: "You're unsubscribed",
    body: `<strong>${escapeHtml(email)}</strong> won't receive any more newsletters from Aaavatar. If this was a mistake, just email <a href="mailto:news@aaavatar.nl">news@aaavatar.nl</a> and we'll add you back.`,
  }));
}

function sendHtml(res: VercelResponse, status: number, html: string) {
  res.status(status);
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.send(html);
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function statusPage({ heading, body }: { heading: string; body: string }): string {
  // Inline-styled, dependency-free. Mail-client preview-pane safe + works
  // when the user clicks through to the live page on any device.
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <meta name="robots" content="noindex,nofollow" />
  <title>Aaavatar — Newsletter</title>
  <style>
    html, body { margin: 0; height: 100%; background: #0B0B0D; color: #E6EAF1;
                 font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; }
    .wrap { min-height: 100%; display: grid; place-items: center; padding: 32px; box-sizing: border-box; }
    .card { max-width: 480px; background: #16161A; border-radius: 12px; padding: 32px; }
    h1 { font-size: 22px; margin: 0 0 12px; font-weight: 600; }
    p { font-size: 15px; line-height: 1.6; margin: 0; color: #C2C7D0; }
    a { color: #9AB6F2; }
  </style>
</head>
<body>
  <main class="wrap">
    <div class="card">
      <h1>${escapeHtml(heading)}</h1>
      <p>${body}</p>
    </div>
  </main>
</body>
</html>`;
}
