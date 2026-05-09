import type { CollectionConfig } from "payload";

/**
 * Image uploads (announcement hero images, newsletter banners). Stored
 * in Supabase Storage's `announcement-media` bucket via the s3Storage
 * plugin configured in `payload.config.ts`.
 *
 * Public read: the macOS app fetches these URLs over plain HTTP, so the
 * bucket must allow anonymous GETs. Configure the bucket's policy to
 * `public` in the Supabase dashboard.
 */
export const Media: CollectionConfig = {
  slug: "media",
  admin: {
    useAsTitle: "filename",
  },
  access: {
    read: () => true, // Public reads — the macOS app pulls images directly.
  },
  upload: {
    mimeTypes: ["image/png", "image/jpeg", "image/webp", "image/gif"],
    imageSizes: [
      {
        name: "hero",
        width: 1280,
        height: 720,
        position: "centre",
      },
      {
        name: "thumbnail",
        width: 400,
        height: 225,
        position: "centre",
      },
    ],
  },
  fields: [
    {
      name: "alt",
      type: "text",
      required: false,
      admin: {
        description: "Used for accessibility and email fallback.",
      },
    },
  ],
};
