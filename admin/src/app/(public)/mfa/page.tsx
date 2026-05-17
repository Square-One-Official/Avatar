"use client";

import { useEffect, useRef, useState } from "react";

/**
 * TOTP entry page (audit HIGH #11). The middleware redirects here whenever
 * a browser hits `/admin/*` without a valid MFA cookie. On successful
 * verification the server sets the cookie and we bounce back to whatever
 * page the user was originally trying to reach (captured in `?next=`).
 *
 * No framework styling dependency — Payload's CSS isn't loaded outside its
 * own route group, so this is plain inline styles. Keep it minimal; it's
 * a single short-lived screen.
 */
export default function MfaPage() {
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      const res = await fetch("/api/mfa/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ code: code.replace(/\s+/g, "") }),
      });
      if (!res.ok) {
        const body = (await res.json().catch(() => ({}))) as { error?: string };
        setError(body.error === "invalid_code" ? "Code incorrect — try again." : "Verification failed.");
        setSubmitting(false);
        return;
      }
      // Bounce back to the original target if the middleware captured one.
      const params = new URLSearchParams(window.location.search);
      const next = params.get("next");
      window.location.replace(next && next.startsWith("/admin") ? next : "/admin");
    } catch {
      setError("Network error — try again.");
      setSubmitting(false);
    }
  }

  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        minHeight: "100vh",
        background: "#0a0a0a",
        color: "#eaeaea",
        fontFamily: "ui-sans-serif, system-ui, -apple-system, sans-serif",
      }}
    >
      <form
        onSubmit={submit}
        style={{
          width: 320,
          padding: 32,
          background: "#141414",
          borderRadius: 12,
          border: "1px solid #262626",
          boxShadow: "0 12px 40px rgba(0,0,0,0.4)",
        }}
      >
        <h1 style={{ fontSize: 18, margin: "0 0 4px", fontWeight: 600 }}>
          Aaavatar Admin
        </h1>
        <p style={{ fontSize: 13, margin: "0 0 24px", color: "#9a9a9a" }}>
          Enter the 6-digit code from your authenticator app.
        </p>
        <input
          ref={inputRef}
          type="text"
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="\d*"
          maxLength={6}
          value={code}
          onChange={(e) => setCode(e.target.value)}
          placeholder="123 456"
          aria-label="6-digit code"
          style={{
            width: "100%",
            boxSizing: "border-box",
            padding: "12px 14px",
            fontSize: 18,
            letterSpacing: 4,
            textAlign: "center",
            background: "#0a0a0a",
            color: "#eaeaea",
            border: "1px solid #2e2e2e",
            borderRadius: 8,
          }}
        />
        {error && (
          <div role="alert" style={{ marginTop: 12, fontSize: 12, color: "#ef4444" }}>
            {error}
          </div>
        )}
        <button
          type="submit"
          disabled={submitting || code.length < 6}
          style={{
            marginTop: 16,
            width: "100%",
            padding: "10px 14px",
            fontSize: 14,
            fontWeight: 600,
            background: submitting || code.length < 6 ? "#262626" : "#2563eb",
            color: "#fff",
            border: "none",
            borderRadius: 8,
            cursor: submitting || code.length < 6 ? "default" : "pointer",
          }}
        >
          {submitting ? "Verifying…" : "Continue"}
        </button>
      </form>
    </div>
  );
}
