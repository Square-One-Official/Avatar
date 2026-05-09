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
  // Postgres on Supabase. The `schema=payload` qualifier in DATABASE_URL
  // confines Payload's tables to a dedicated schema so they never collide
  // with the existing public.* tables (users, subscriptions, etc.).
  db: postgresAdapter({
    pool: {
      connectionString: process.env.DATABASE_URL ?? "",
    },
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
