/**
 * Root layout. Required by Next.js App Router for any page outside a
 * route group's own layout (e.g. `src/app/page.tsx`, which redirects
 * `/` → `/admin`). Payload's pages live under `(payload)/` and use
 * their own `RootLayout` from `@payloadcms/next`, so this minimal
 * shell only renders for the bare-host redirect.
 */
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
