import type { VercelRequest, VercelResponse } from "@vercel/node";

/**
 * GET /auth-callback
 *
 * Bridge page for Supabase Google OAuth on the macOS app.
 *
 * Why this exists: Supabase's OAuth redirect cannot point directly at the
 * `aaavatar://auth-callback` custom scheme — well, it can, but then the
 * browser tab is left dangling on a `about:blank`-ish error after handing off
 * to the OS, which is confusing for users. Instead Supabase redirects here,
 * we forward the same query+fragment to `aaavatar://auth-callback`, and show
 * a "you can close this tab" page so the user knows the round-trip succeeded.
 *
 * Both PKCE (`?code=...`) and implicit (`#access_token=...`) flows are
 * preserved by re-emitting `location.search` and `location.hash` verbatim.
 *
 * Add `https://api.aaavatar.nl/auth-callback` to Supabase Auth → URL
 * Configuration → Redirect URLs for this to work in production.
 */
export default function handler(_req: VercelRequest, res: VercelResponse) {
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  // The page is self-contained — no external assets — so it works even if the
  // user's network drops between the OAuth redirect and the deep-link bounce.
  res.status(200).send(HTML);
}

const HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Signed in — Avatar</title>
<style>
  :root {
    color-scheme: light dark;
    --bg: #f7f7f5;
    --fg: #111111;
    --muted: #6b6b6b;
    --card: #ffffff;
    --border: rgba(0,0,0,0.08);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0e0e0e;
      --fg: #f2f2f2;
      --muted: #9a9a9a;
      --card: #161616;
      --border: rgba(255,255,255,0.08);
    }
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; margin: 0; }
  body {
    background: var(--bg);
    color: var(--fg);
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter",
                 system-ui, sans-serif;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
    -webkit-font-smoothing: antialiased;
  }
  main {
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 16px;
    padding: 40px 36px;
    max-width: 420px;
    width: 100%;
    text-align: center;
    box-shadow: 0 1px 2px rgba(0,0,0,0.04), 0 12px 32px rgba(0,0,0,0.06);
  }
  .check {
    width: 56px;
    height: 56px;
    margin: 0 auto 20px;
    border-radius: 50%;
    background: #1f9d55;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .check svg { width: 28px; height: 28px; color: #fff; }
  h1 {
    font-size: 22px;
    font-weight: 600;
    letter-spacing: -0.01em;
    margin: 0 0 8px;
  }
  p {
    margin: 0;
    color: var(--muted);
    font-size: 15px;
    line-height: 1.5;
  }
  p + p { margin-top: 14px; }
  .retry {
    display: inline-block;
    margin-top: 18px;
    font-size: 14px;
    color: var(--fg);
    text-decoration: underline;
    text-underline-offset: 3px;
    cursor: pointer;
  }
</style>
</head>
<body>
  <main>
    <div class="check" aria-hidden="true">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3"
           stroke-linecap="round" stroke-linejoin="round">
        <polyline points="20 6 9 17 4 12"></polyline>
      </svg>
    </div>
    <h1>You're signed in</h1>
    <p>Avatar will open automatically. You can close this tab.</p>
    <p id="fallback" hidden>
      Nothing happened? <a class="retry" id="retry" href="#">Open Avatar again</a>
    </p>
  </main>
<script>
  (function () {
    // Forward the exact query + fragment Supabase handed us to the app's
    // custom URL scheme. Both the PKCE (?code=...) and implicit
    // (#access_token=...) flows are covered by preserving search+hash verbatim.
    var deepLink = "aaavatar://auth-callback"
                 + (window.location.search || "")
                 + (window.location.hash || "");

    function open() { window.location.replace(deepLink); }

    // Kick off the deep link immediately.
    open();

    // If macOS doesn't bounce focus back to the browser after a couple of
    // seconds, surface a manual retry link — covers the case where the user
    // dismissed the "Open Avatar?" system prompt.
    setTimeout(function () {
      var fb = document.getElementById("fallback");
      if (fb) fb.hidden = false;
      var retry = document.getElementById("retry");
      if (retry) retry.addEventListener("click", function (e) {
        e.preventDefault();
        open();
      });
    }, 2500);
  })();
</script>
</body>
</html>
`;
