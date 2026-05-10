import path from "path";
import { fileURLToPath } from "url";
import { buildConfig } from "payload";
import { postgresAdapter } from "@payloadcms/db-postgres";
import { lexicalEditor } from "@payloadcms/richtext-lexical";
import { s3Storage } from "@payloadcms/storage-s3";

import { Users } from "./collections/Users";
import { Media } from "./collections/Media";
import { Announcements } from "./collections/Announcements";
import { BadgeComponents } from "./collections/BadgeComponents";
import { sendNewsletterEndpoint } from "./endpoints/sendNewsletter";

const dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * Append `schema=payload` to a Postgres connection string if it's not
 * already there. Idempotent — calling on an already-qualified URL is a
 * no-op. Empty string in → empty string out so a missing env doesn't
 * produce a malformed URL that obscures the underlying config issue.
 */
function ensureSchema(url: string): string {
  if (!url) return url;
  if (/[?&]schema=/.test(url)) return url;
  return `${url}${url.includes("?") ? "&" : "?"}schema=payload`;
}

export default buildConfig({
  admin: {
    user: Users.slug,
    meta: {
      titleSuffix: " — Aaavatar Admin",
    },
  },
  editor: lexicalEditor(),
  collections: [Users, Media, Announcements, BadgeComponents],
  endpoints: [sendNewsletterEndpoint],
  secret: process.env.PAYLOAD_SECRET ?? "",
  typescript: {
    outputFile: path.resolve(dirname, "payload-types.ts"),
  },
  // Postgres on Supabase. The `?schema=payload` qualifier confines
  // Payload's tables to a dedicated schema so they never collide with
  // the existing public.* tables (users, subscriptions, etc.).
  //
  // Source preference: prefer the explicit DATABASE_URL, fall back to
  // POSTGRES_URL_NON_POOLING (auto-injected by Vercel's Supabase
  // integration). The non-pooled connection is used because Payload
  // migrations don't tolerate pgbouncer's transaction-mode pooling
  // (LISTEN/NOTIFY, prepared statements). For serverless runtime that's
  // a few extra ms; the admin app is low-traffic so the simplicity wins.
  db: postgresAdapter({
    pool: {
      connectionString: ensureSchema(
        process.env.DATABASE_URL ??
          process.env.POSTGRES_URL_NON_POOLING ??
          "",
      ),
    },
    // Auto-create / sync tables on startup. Safe here because Payload
    // owns the `payload` schema exclusively — no other consumer's
    // tables can be clobbered. Without this, the very first request
    // fails with "Failed query: select users.id..." because Payload
    // never gets a chance to materialise its schema.
    push: true,
  }),
  plugins: [
    // Supabase Storage exposes an S3-compatible endpoint; the same
    // adapter that points at AWS works against it.
    s3Storage({
      collections: {
        media: {
          prefix: "media",
        },
      },
      bucket: process.env.S3_BUCKET ?? "announcement-media",
      config: {
        endpoint: process.env.S3_ENDPOINT,
        region: process.env.S3_REGION ?? "eu-central-1",
        credentials: {
          accessKeyId: process.env.S3_ACCESS_KEY_ID ?? "",
          secretAccessKey: process.env.S3_SECRET_ACCESS_KEY ?? "",
        },
        forcePathStyle: true,
      },
    }),
  ],
  cors: ["https://api.aaavatar.nl", "http://localhost:3000"],
  csrf: ["https://admin.aaavatar.nl"],
});
