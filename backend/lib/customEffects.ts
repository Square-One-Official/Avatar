import { randomUUID } from "node:crypto";
import { supabase } from "./supabase.js";

/**
 * Per-user custom Effects (E34). A Pro user creates an Effect from a reference
 * image + a short description (see /v1/custom-effects). The reference image
 * lives in the public `custom-effects` Storage bucket so the macOS client can
 * render the card thumbnail straight from its URL; /v1/stylize re-reads the
 * same object server-side to pass it to the model as a style reference.
 *
 * The row's `prompt` is the user's description — kept server-side like the
 * built-in CMS effect prompts (only /v1/stylize reads it).
 */
export const CUSTOM_EFFECTS_BUCKET = "custom-effects";

const SUPABASE_URL = process.env.SUPABASE_URL!;

export type CustomEffectRow = {
  id: string;
  owner_id: string;
  label: string;
  prompt: string;
  reference_path: string;
  created_at: string;
};

/** Public object URL for a reference image (bucket is public). */
export function customEffectThumbnailUrl(referencePath: string): string {
  return `${SUPABASE_URL}/storage/v1/object/public/${CUSTOM_EFFECTS_BUCKET}/${referencePath}`;
}

/** All of a user's custom effects, newest first. */
export async function listCustomEffects(userId: string): Promise<CustomEffectRow[]> {
  const { data, error } = await supabase
    .from("custom_effects")
    .select("*")
    .eq("owner_id", userId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data as CustomEffectRow[] | null) ?? [];
}

/** A single custom effect owned by `userId`, or null. */
export async function getCustomEffect(
  userId: string,
  id: string,
): Promise<CustomEffectRow | null> {
  const { data, error } = await supabase
    .from("custom_effects")
    .select("*")
    .eq("owner_id", userId)
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return (data as CustomEffectRow | null) ?? null;
}

/**
 * Creates a custom effect: uploads the reference PNG to the public bucket
 * (path `<userId>/<effectId>.png`) and inserts the row. Returns the new row.
 * On a DB-insert failure the just-uploaded object is best-effort removed so we
 * don't orphan storage.
 */
export async function createCustomEffect(opts: {
  userId: string;
  label: string;
  prompt: string;
  referenceBytes: Buffer;
}): Promise<CustomEffectRow> {
  const id = randomUUID();
  const referencePath = `${opts.userId}/${id}.png`;

  const { error: upErr } = await supabase.storage
    .from(CUSTOM_EFFECTS_BUCKET)
    .upload(referencePath, opts.referenceBytes, {
      contentType: "image/png",
      upsert: true,
    });
  if (upErr) throw upErr;

  const { data, error } = await supabase
    .from("custom_effects")
    .insert({
      id,
      owner_id: opts.userId,
      label: opts.label,
      prompt: opts.prompt,
      reference_path: referencePath,
    })
    .select("*")
    .single();

  if (error) {
    await supabase.storage.from(CUSTOM_EFFECTS_BUCKET).remove([referencePath]);
    throw error;
  }
  return data as CustomEffectRow;
}

/**
 * Deletes a user's custom effect (row + reference object). Returns false when
 * no matching row exists for this owner (so the caller can 404).
 */
export async function deleteCustomEffect(userId: string, id: string): Promise<boolean> {
  const existing = await getCustomEffect(userId, id);
  if (!existing) return false;

  const { error } = await supabase
    .from("custom_effects")
    .delete()
    .eq("owner_id", userId)
    .eq("id", id);
  if (error) throw error;

  // Best-effort storage cleanup; a leftover object is harmless (orphaned, and
  // the row — the only thing the client lists — is already gone).
  const { error: rmErr } = await supabase.storage
    .from(CUSTOM_EFFECTS_BUCKET)
    .remove([existing.reference_path]);
  if (rmErr) console.warn("[customEffects] reference remove failed", rmErr);

  return true;
}

/**
 * Downloads a custom effect's reference image bytes from the public bucket,
 * for /v1/stylize to pass to the model as a style reference. The bucket is
 * public, so a plain object fetch is enough (no signed URL needed).
 */
export async function downloadReferenceBytes(referencePath: string): Promise<Buffer> {
  const { data, error } = await supabase.storage
    .from(CUSTOM_EFFECTS_BUCKET)
    .download(referencePath);
  if (error || !data) {
    throw error ?? new Error("custom effect reference download returned no data");
  }
  return Buffer.from(await data.arrayBuffer());
}
