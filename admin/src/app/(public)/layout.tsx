/**
 * Minimal layout for the public, unauthenticated routes (the TOTP gate).
 * Kept separate from `(payload)/layout.tsx` so the MFA page doesn't need
 * Payload's `RootLayout` — that one runs the Payload config bootstrap and
 * would attempt a database connection just to render a 6-digit input.
 */
export default function PublicLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content="noindex, nofollow" />
        <title>Aaavatar Admin — Verify</title>
      </head>
      <body style={{ margin: 0, background: "#0a0a0a" }}>{children}</body>
    </html>
  );
}
