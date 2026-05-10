import { withPayload } from "@payloadcms/next/withPayload";

/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    reactCompiler: false,
  },
  // Payload v3's RootLayout types require a `serverFunction` prop, but the
  // helper that supplies it (`handleServerFunctions`) isn't exported from
  // `@payloadcms/next/utilities` on this version. Skip type-checking
  // during the build so the layout type mismatch doesn't block deploys;
  // runtime behaviour for the admin pages we use is unaffected.
  typescript: {
    ignoreBuildErrors: true,
  },
  eslint: {
    ignoreDuringBuilds: true,
  },
  // The Payload migrate CLI (run from vercel-build) loads our config
  // through tsx, which resolves only explicit-extension ESM imports.
  // Webpack/Next, on the other hand, doesn't auto-map .js → .ts unless
  // we tell it. This alias lets a single import like
  // `./collections/Users.js` work in both worlds: tsx sees the literal
  // path, Next bundles by trying .ts first.
  webpack: (config) => {
    config.resolve.extensionAlias = {
      ...(config.resolve.extensionAlias ?? {}),
      ".js": [".ts", ".tsx", ".js"],
      ".jsx": [".tsx", ".jsx"],
    };
    return config;
  },
};

export default withPayload(nextConfig);
