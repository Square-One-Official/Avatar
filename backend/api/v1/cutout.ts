import type { VercelRequest, VercelResponse } from "@vercel/node";
import { checkRateLimit, requireUser } from "../../lib/auth.js";
import { MODEL_REGISTRY, resolveModelOverride, UnknownModelOverrideError } from "../../lib/models.js";
import { proOverrideFor } from "../../lib/proAccess.js";
import {
  currentCredits,
  ensureCompedCredits,
  ensureUser,
  freeCutoutsUsed,
  logCredit,
  tryConsumeFreeCutout,
  FREE_CUTOUTS_ALLOWANCE,
} from "../../lib/supabase.js";
import { supabase } from "../../lib/supabase.js";
import { magicCutout, ReplicateTimeoutError } from "../../lib/replicate.js";

/**
 * POST /v1/cutout
 *
 * Body:    { storage_key: "<userId>/<uuid>.png" }
 * Returns: 200 { cutout: <base64 PNG>, credits_remaining: int }
 *          400 { error: "missing_storage_key" | "invalid_storage_key" }
 *          402 { error: "insufficient_credits", credits_remaining: 0 }
 *          401 { error: "unauthorized" }
 *          429 { error: "rate_limited" }
 *
 * The client uploads its PNG to the `cutout-uploads` bucket via a signed PUT
 * URL (see `/v1/cutout/upload-url`) and hands us back the resulting object
 * key. We sign a short-lived READ URL for that key and pass it straight to
 * Replicate — BiRefNet pulls the image itself, so the bytes never traverse
 * Vercel and we sidestep the 4.5 MB serverless body cap entirely.
 *
 * Pricing model — credits are tried first, then the free trial (unchanged
 * from the previous base64 path):
 *   - User has ≥ 1 credit (subscription grant or topup leftovers): spend
 *     1 credit, logged to credit_ledger.
 *   - Otherwise, free user under FREE_CUTOUTS_ALLOWANCE: claim a trial
 *     slot via the atomic SQL function (no ledger entry).
 *   - Otherwise: 402.
 *
 * Errors before the model call don't deduct; errors during the model call
 * don't deduct either (we only commit the spend after the result lands).
 *
 * Dev-allowlisted users (DEV_UNLIMITED_EMAILS) skip both gates so the
 * developer can iterate without burning credits or trial slots.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const user = await requireUser(req, res);
  if (!user) return;

  if (!(await checkRateLimit(user.id))) {
    res.status(429).json({ error: "rate_limited" });
    return;
  }

  const storageKey = (req.body?.storage_key ?? "") as string;
  if (!storageKey || typeof storageKey !== "string") {
    res.status(400).json({ error: "missing_storage_key" });
    return;
  }
  // Defense in depth: the upload-url endpoint already namespaces keys under
  // the caller's id, but we revalidate here so a malicious client can't pass
  // a key from another user's prefix.
  if (!storageKey.startsWith(`${user.id}/`) || storageKey.includes("..")) {
    res.status(400).json({ error: "invalid_storage_key" });
    return;
  }

  // E14.9 — the Pro list: CMS `pro-access` first, DEV_UNLIMITED_EMAILS as
  // break-glass. "unlimited" skips credit accounting entirely; a comped Pro
  // gets this month's allowance and then spends credits like anyone else.
  const override = await proOverrideFor(user.email);
  const isDevUser = override?.mode === "unlimited";
  if (override?.mode === "pro") {
    await ensureCompedCredits(user.id, override.monthlyCredits);
  }

  // E01.10: optional model override — dev-only, whitelist in MODEL_REGISTRY.
  let modelRef: string | null;
  try {
    modelRef = resolveModelOverride("cutout", req.body?.model_override, isDevUser);
  } catch (e) {
    if (e instanceof UnknownModelOverrideError) {
      res.status(400).json({ error: "unknown_model_override" });
      return;
    }
    throw e;
  }

  type SpendMode = "credit" | "free_trial" | "dev";

  try {
    await ensureUser(user.id);

    let mode: SpendMode;
    if (isDevUser) {
      mode = "dev";
    } else {
      const credits = await currentCredits(user.id);
      if (credits >= MODEL_REGISTRY.cutout.credits) {
        mode = "credit";
      } else {
        const used = await freeCutoutsUsed(user.id);
        if (used >= FREE_CUTOUTS_ALLOWANCE) {
          res.status(402).json({ error: "insufficient_credits", credits_remaining: 0 });
          return;
        }
        mode = "free_trial";
      }
    }

    // 5-minute TTL is more than enough for Replicate to fetch the input
    // before BiRefNet runs (cold-start + warm-up rarely exceeds 60s).
    //
    // Audit MEDIUM #21: don't log the full signed URLs (they grant 5-min
    // read access to the bytes) or the raw storage key (contains the
    // userId). Diagnostics only need the step + a short tag.
    console.log("[/v1/cutout] step=sign storageKey=", redactKey(storageKey));
    const { data: signed, error: signErr } = await supabase.storage
      .from("cutout-uploads")
      .createSignedUrl(storageKey, 300);
    if (signErr || !signed?.signedUrl) {
      console.error("[/v1/cutout] sign error", signErr);
      res.status(500).json({ error: "cutout_failed", step: "sign" });
      return;
    }
    console.log("[/v1/cutout] step=replicate url=<redacted>");

    let resultUrl: string;
    try {
      resultUrl = await magicCutout({ imageDataUrl: signed.signedUrl, model: modelRef });
    } catch (e) {
      // Message only — the Replicate SDK embeds the auth header in the full
      // error object, so logging `e` whole leaks REPLICATE_API_TOKEN.
      console.error("[/v1/cutout] replicate error:", e instanceof Error ? e.message : String(e));
      // Audit MEDIUM #17: distinguish a timeout from a model error so the
      // client can show a friendlier "model is taking longer than usual"
      // banner instead of "cutout failed".
      if (e instanceof ReplicateTimeoutError) {
        res.status(504).json({ error: "model_timeout", step: "replicate" });
        return;
      }
      res.status(500).json({ error: "cutout_failed", step: "replicate" });
      return;
    }
    console.log("[/v1/cutout] step=download resultUrl=<redacted>");

    const download = await fetch(resultUrl);
    if (!download.ok) {
      throw new Error(`Replicate result fetch failed: ${download.status}`);
    }
    const cutoutBytes = Buffer.from(await download.arrayBuffer());
    console.log("[/v1/cutout] step=deduct mode=", mode, "bytes=", cutoutBytes.length);
    // No `resultUrl` in the log — it's a Replicate-signed download URL.
    // For incident traceability we still keep the prediction reference
    // in the credit_ledger row below, which is operator-only.

    // Deduct only after we have the bytes in hand.
    if (mode === "credit") {
      await logCredit({
        userId: user.id,
        delta: -MODEL_REGISTRY.cutout.credits,
        reason: "magic_cutout",
        ref: resultUrl,
      });
    } else if (mode === "free_trial") {
      await tryConsumeFreeCutout(user.id);
    }

    // Best-effort cleanup so the bucket doesn't accumulate inputs. We await
    // the delete because Vercel terminates the function as soon as the
    // response lands — fire-and-forget after `res.send()` isn't reliable.
    // The added latency is negligible against the Replicate call we just
    // finished, and the user already has their result regardless.
    const { error: rmErr } = await supabase.storage
      .from("cutout-uploads")
      .remove([storageKey]);
    if (rmErr) console.warn("cutout-uploads remove failed", storageKey, rmErr);

    const creditsRemaining =
      mode === "dev" ? 999 : await currentCredits(user.id);
    res.status(200).json({
      cutout: cutoutBytes.toString("base64"),
      credits_remaining: creditsRemaining,
    });
  } catch (err) {
    console.error("/v1/cutout error:", err instanceof Error ? err.message : String(err));
    res.status(500).json({ error: "cutout_failed" });
  }
}

/**
 * Truncate a storage key to a short, non-identifying tag for logs. The
 * raw key is `<userId>/<uuid>.png` — logging the full path leaks the
 * userId to whoever has Vercel-logs read access. Keep only the last 8
 * chars of the UUID so a developer can still correlate a failure to the
 * upload object if they need to.
 */
function redactKey(key: string): string {
  const dot = key.lastIndexOf(".");
  const stem = dot > 0 ? key.slice(0, dot) : key;
  const tail = stem.slice(-8);
  return `…/${tail}`;
}
