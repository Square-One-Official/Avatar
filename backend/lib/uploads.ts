import { randomUUID } from "node:crypto";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import sharp from "sharp";
import { supabase } from "./supabase.js";
import { MAX_DECODED_IMAGE_BYTES, MAX_INPUT_IMAGE_PIXELS } from "./image.js";

/**
 * Raster formats the image pipeline (`flattenOnGrey`, `padForOutpaint`, …)
 * can legitimately process. Deliberately excludes `svg` so a vector payload
 * can never reach sharp's SVG/librsvg parsing surface, and rejects anything
 * sharp can't identify (which would otherwise throw a 500 deeper in the
 * pipeline). The `cutout-uploads` bucket is already PNG-only on the
 * signed-URL path; this also covers the legacy inline-base64 path, which has
 * no MIME enforcement of its own.
 */
const ALLOWED_RASTER_FORMATS = new Set([
  "png",
  "jpeg",
  "webp",
  "gif",
  "tiff",
  // sharp/libvips report BOTH AVIF and HEIC as "heif" (AVIF is demuxed through
  // libheif); there is no distinct "avif" format string from metadata(), so
  // this single entry admits both. Don't remove it expecting to only drop HEIC
  // — that would silently also reject AVIF.
  "heif",
]);

/**
 * Reject inputs that aren't a supported raster bitmap, or that decode to an
 * implausibly large pixel grid (decompression bomb). Returns `true` when the
 * bytes are safe to hand downstream; otherwise writes a 400 and returns
 * `false`. Uses `metadata()` (header parse only — no full decode).
 */
async function assertProcessableImage(bytes: Buffer, res: VercelResponse): Promise<boolean> {
  let format: string | undefined;
  let width: number | undefined;
  let height: number | undefined;
  try {
    ({ format, width, height } = await sharp(bytes).metadata());
  } catch {
    res.status(400).json({ error: "invalid_image" });
    return false;
  }
  if (!format || !ALLOWED_RASTER_FORMATS.has(format)) {
    res.status(400).json({ error: "unsupported_image_format" });
    return false;
  }
  if ((width ?? 0) * (height ?? 0) > MAX_INPUT_IMAGE_PIXELS) {
    res.status(400).json({ error: "image_dimensions_out_of_range" });
    return false;
  }
  return true;
}

/**
 * Shared input-image resolution for the image-processing endpoints
 * (/v1/stylize, /v1/colorize, /v1/fill-body, /v1/upscale).
 *
 * Supports TWO body shapes:
 *   - `{ storage_key: "<userId>/<uuid>.png" }` — the upload-bypass: the
 *     client uploaded the PNG straight to the `cutout-uploads` bucket via a
 *     signed PUT URL (see /v1/cutout/upload-url), so the bytes never traverse
 *     Vercel's ~4.5 MB serverless request-body cap. We sign a short-lived
 *     READ URL, download the bytes into the function, and delete the object.
 *   - `{ image: "<base64 PNG>" }` — the legacy inline path, kept for
 *     backward compatibility with older app builds (and small payloads).
 *
 * Unlike /v1/cutout (which hands the signed READ URL straight to Replicate),
 * these endpoints must process the bytes server-side (flatten/pad + sharp)
 * before calling Replicate, so we download here. The object is unneeded the
 * moment we hold the bytes, so it's deleted immediately (best-effort).
 *
 * On any client/transport error this sends the matching response and returns
 * `null` — callers follow the `requireUser` convention and just `return`.
 */
const BUCKET = "cutout-uploads";

export async function resolveImageInput(
  req: VercelRequest,
  res: VercelResponse,
  userId: string,
): Promise<Buffer | null> {
  const storageKey = (req.body?.storage_key ?? "") as string;

  if (storageKey) {
    // Defense in depth: the upload-url endpoint already namespaces keys under
    // the caller's id, but revalidate so a client can't pass another user's
    // key (mirrors the /v1/cutout check).
    if (
      typeof storageKey !== "string" ||
      !storageKey.startsWith(`${userId}/`) ||
      storageKey.includes("..")
    ) {
      res.status(400).json({ error: "invalid_storage_key" });
      return null;
    }

    let bytes: Buffer;
    try {
      console.log("[uploads] step=sign storageKey=", redactKey(storageKey));
      const { data: signed, error: signErr } = await supabase.storage
        .from(BUCKET)
        .createSignedUrl(storageKey, 300);
      if (signErr || !signed?.signedUrl) {
        console.error("[uploads] sign error", signErr);
        res.status(500).json({ error: "input_fetch_failed", step: "sign" });
        return null;
      }
      const dl = await fetch(signed.signedUrl);
      if (!dl.ok) {
        console.error("[uploads] download failed", dl.status);
        res.status(500).json({ error: "input_fetch_failed", step: "download" });
        return null;
      }
      bytes = Buffer.from(await dl.arrayBuffer());
    } catch (err) {
      console.error("[uploads] fetch error", err);
      res.status(500).json({ error: "input_fetch_failed" });
      return null;
    }

    // Bytes are in hand → the upload object is done. Best-effort cleanup so
    // the bucket doesn't accumulate inputs (same as /v1/cutout).
    const { error: rmErr } = await supabase.storage.from(BUCKET).remove([storageKey]);
    if (rmErr) console.warn("[uploads] remove failed", redactKey(storageKey), rmErr);

    if (bytes.length === 0 || bytes.length > MAX_DECODED_IMAGE_BYTES) {
      res.status(400).json({ error: "image_size_out_of_range" });
      return null;
    }
    if (!(await assertProcessableImage(bytes, res))) return null;
    return bytes;
  }

  // Legacy inline base64 path.
  const base64 = (req.body?.image ?? "") as string;
  if (!base64 || typeof base64 !== "string") {
    res.status(400).json({ error: "missing_image" });
    return null;
  }
  const cleaned = base64.replace(/^data:image\/[a-z]+;base64,/i, "");
  let bytes: Buffer;
  try {
    bytes = Buffer.from(cleaned, "base64");
  } catch {
    res.status(400).json({ error: "invalid_base64" });
    return null;
  }
  if (bytes.length === 0 || bytes.length > MAX_DECODED_IMAGE_BYTES) {
    res.status(400).json({ error: "image_size_out_of_range" });
    return null;
  }
  if (!(await assertProcessableImage(bytes, res))) return null;
  return bytes;
}

/**
 * The OUTPUT counterpart to `resolveImageInput`. Generated RESULT images
 * (full-frame, opaque backgrounds up to 2048²) can exceed Vercel's
 * ~4.5 MB serverless RESPONSE body cap when returned inline as base64 —
 * the body truncates, the client's decode fails, and the user is left with
 * a charged credit and no image. So we upload the result to a private
 * bucket and hand the client a short-lived signed READ URL it downloads
 * straight from Supabase Storage instead.
 *
 * Throws on upload/sign failure so the caller can abort BEFORE charging a
 * credit — a generation that can't be delivered must never bill the user.
 *
 * Returns both the signed `url` (handed to the client) and the durable
 * storage `key` (`<userId>/<uuid>.<ext>`) — the latter is the stable artifact
 * reference to log in the credit ledger, since the signed URL expires.
 * Objects are swept by api/cron/sweep-generated-results.
 */
export const RESULT_BUCKET = "generated-results";

export async function uploadResultImage(
  userId: string,
  bytes: Buffer,
  ext = "webp",
): Promise<{ url: string; key: string }> {
  const key = `${userId}/${randomUUID()}.${ext}`;
  const contentType =
    ext === "webp" ? "image/webp" : ext === "png" ? "image/png" : "image/jpeg";

  const { error: upErr } = await supabase.storage
    .from(RESULT_BUCKET)
    .upload(key, bytes, { contentType, upsert: false });
  if (upErr) throw new Error(`result upload failed: ${upErr.message}`);

  const { data: signed, error: signErr } = await supabase.storage
    .from(RESULT_BUCKET)
    .createSignedUrl(key, 600);
  if (signErr || !signed?.signedUrl) {
    throw new Error(`result sign failed: ${signErr?.message ?? "no signed url"}`);
  }
  return { url: signed.signedUrl, key };
}

/**
 * Truncate a storage key (`<userId>/<uuid>.png`) to a short, non-identifying
 * tag for logs so the userId never lands in Vercel logs.
 */
function redactKey(key: string): string {
  const dot = key.lastIndexOf(".");
  const stem = dot > 0 ? key.slice(0, dot) : key;
  return `…/${stem.slice(-8)}`;
}
