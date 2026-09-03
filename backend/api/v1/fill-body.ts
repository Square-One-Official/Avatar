import type { VercelRequest, VercelResponse } from "@vercel/node";
import { randomUUID } from "node:crypto";
import { checkRateLimit, requireUser } from "../../lib/auth.js";
import { MODEL_REGISTRY, resolveModelOverride, UnknownModelOverrideError } from "../../lib/models.js";
import { proOverrideFor } from "../../lib/proAccess.js";
import {
  currentCredits,
  ensureCompedCredits,
  ensureUser,
  refundCreditSpend,
  trySpendCredits,
} from "../../lib/supabase.js";
import {
  prepareMinimalBodyFill,
  restoreMinimalBodyFillSubject,
  type FillBodyEdges,
  type FillBodyMapping,
} from "../../lib/image.js";
import { resolveImageInput } from "../../lib/uploads.js";
import { magicCutout, outpaintPortrait, ReplicateTimeoutError } from "../../lib/replicate.js";

export const config = {
  api: {
    bodyParser: { sizeLimit: "15mb" },
  },
};

/**
 * POST /v1/fill-body
 *
 * Body:    { image?: <base64 PNG with alpha>,        // legacy inline
 *            storage_key?: "<userId>/<uuid>.png" }   // upload-bypass (groot beeld)
 * Returns: 200 success
 *            { cutout: <base64 PNG>, credits_remaining: int }
 *          402 insufficient_credits
 *          401 unauthorized
 *          429 rate_limited
 *
 * Pipeline (real outpainting, not instruction-edit):
 *   1. Detect straight crop lines on the subject's alpha bbox (left/right/
 *      bottom) — a transparent gutter around the subject does not hide a cut
 *      (E56.2). If nothing is cropped, return the original cutout without
 *      invoking Replicate or charging.
 *   2. Grow the canvas only where the existing margin can't hold the strip,
 *      and build a white-on-fill mask covering one strip past each crop line.
 *   3. Check credits (402 if empty).
 *   4. Run FLUX.1 Fill Pro on (image, mask). It only paints into the
 *      masked region.
 *   5. Re-extract alpha via BiRefNet (`magicCutout`) so the client gets
 *      a transparent cutout consistent with `/v1/cutout`'s output shape.
 *   6. Log the configured credit cost and return the new cutout + mapping.
 *
 * Errors before the credit-deducting Replicate call don't charge.
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

  // Input: inline base64 (legacy) of een Storage-upload (storage_key,
  // omzeilt de 4.5 MB body-cap).
  const inputBytes = await resolveImageInput(req, res, user.id);
  if (!inputBytes) return;

  // Optional face bbox from the client (Apple Vision on the pre-fill
  // cutout). Normalised 0..1, top-left origin. Drives the strict
  // face-protection mask in padForOutpaint. Anything malformed is
  // dropped silently — the heuristic fallback still protects the head.
  let faceBox: { x: number; y: number; width: number; height: number } | undefined;
  const rawFace = req.body?.face;
  if (rawFace && typeof rawFace === "object") {
    const f = rawFace as Record<string, unknown>;
    if (
      typeof f.x === "number" &&
      typeof f.y === "number" &&
      typeof f.width === "number" &&
      typeof f.height === "number" &&
      f.x >= 0 && f.y >= 0 &&
      f.width > 0 && f.height > 0 &&
      f.x + f.width <= 1.001 &&
      f.y + f.height <= 1.001
    ) {
      faceBox = { x: f.x, y: f.y, width: f.width, height: f.height };
    }
  }

  // E14.9 — the Pro list: CMS `pro-access` first, DEV_UNLIMITED_EMAILS as
  // break-glass. "unlimited" skips credit accounting entirely; a comped Pro
  // gets this month's allowance and then spends credits like anyone else.
  const override = await proOverrideFor(user.email);
  const isDevUser = override?.mode === "unlimited";
  if (override?.mode === "pro") {
    await ensureCompedCredits(user.id, override.monthlyCredits);
  }

  // E01.10: optional model override voor de outpaint-stap — dev-only,
  // whitelist in MODEL_REGISTRY. De alpha-herextractie (stap 4) blijft
  // bewust op het cutout-default: die stap is interne plumbing, geen
  // bakeoff-onderwerp.
  let modelRef: string | null;
  let reservedCreditRef: string | null = null;
  try {
    modelRef = resolveModelOverride("fill_body", req.body?.model_override, isDevUser);
  } catch (e) {
    if (e instanceof UnknownModelOverrideError) {
      res.status(400).json({ error: "unknown_model_override" });
      return;
    }
    throw e;
  }

  try {
    await ensureUser(user.id);

    // Step 1: build an edge-aware outpaint canvas. Pure server-side image
    // work, no Replicate calls — safe to do before the credit gate.
    const preparation = await prepareMinimalBodyFill(inputBytes, { face: faceBox });
    if (!preparation.shouldFill) {
      const creditsRemaining = isDevUser ? 999 : await currentCredits(user.id);
      res.status(200).json({
        cutout: preparation.cutout.toString("base64"),
        credits_remaining: creditsRemaining,
        did_fill: false,
        mapping: wireMapping(preparation.mapping),
        filled_edges: wireEdges(preparation.edges),
      });
      return;
    }
    const { padded, mask, personLayer, mapping, edges } = preparation;
    const paddedDataUrl = `data:image/png;base64,${padded.toString("base64")}`;
    const maskDataUrl = `data:image/png;base64,${mask.toString("base64")}`;

    // Step 2: atomically reserve credits only after geometry proves this is
    // billable, but before either paid model runs.
    let creditsRemaining = 999;
    if (!isDevUser) {
      reservedCreditRef = randomUUID();
      const remaining = await trySpendCredits({
        userId: user.id,
        amount: MODEL_REGISTRY.fill_body.credits,
        reason: "fill_body",
        ref: reservedCreditRef,
      });
      if (remaining === null) {
        reservedCreditRef = null;
        res.status(402).json({ error: "insufficient_credits", credits_remaining: 0 });
        return;
      }
      creditsRemaining = remaining;
    }

    // Step 3: FLUX Fill Pro paints into the masked margin only.
    const filledUrl = await outpaintPortrait({
      imageDataUrl: paddedDataUrl,
      maskDataUrl,
      model: modelRef,
    });
    const filledDownload = await fetch(filledUrl);
    if (!filledDownload.ok) {
      throw new Error(`Flux Fill result fetch failed: ${filledDownload.status}`);
    }
    const filledBytes = Buffer.from(await filledDownload.arrayBuffer());
    const filledDataUrl = `data:image/png;base64,${filledBytes.toString("base64")}`;

    // Step 4: BiRefNet to re-extract alpha so the client receives a
    // transparent cutout consistent with /v1/cutout's shape.
    const cutoutUrl = await magicCutout({ imageDataUrl: filledDataUrl });
    const cutoutDownload = await fetch(cutoutUrl);
    if (!cutoutDownload.ok) {
      throw new Error(`BiRefNet result fetch failed: ${cutoutDownload.status}`);
    }
    const cutoutBytes = Buffer.from(await cutoutDownload.arrayBuffer());

    // Step 4b: restore the original clean person over the re-matted result.
    // BiRefNet re-extracts alpha across the whole canvas, which re-contaminates
    // the hair edges (flattened onto grey in step 1) into a light halo. The
    // person should round-trip unchanged — only the newly painted body needs
    // the fresh matte. This composites the clean person back and drops the halo.
    const finalCutout = await restoreMinimalBodyFillSubject(cutoutBytes, personLayer, mapping);

    res.status(200).json({
      cutout: finalCutout.toString("base64"),
      credits_remaining: creditsRemaining,
      did_fill: true,
      mapping: wireMapping(mapping),
      filled_edges: wireEdges(edges),
    });
    reservedCreditRef = null;
  } catch (err) {
    if (reservedCreditRef) {
      try {
        await refundCreditSpend({
          userId: user.id,
          amount: MODEL_REGISTRY.fill_body.credits,
          reason: "fill_body",
          ref: reservedCreditRef,
        });
      } catch (refundError) {
        const refundMessage = refundError instanceof Error
          ? refundError.message
          : String(refundError);
        console.error("/v1/fill-body credit refund failed:", refundMessage);
      }
      reservedCreditRef = null;
    }
    // Log the message only — the Replicate SDK embeds the auth header in the
    // full error object, so logging `err` whole leaks REPLICATE_API_TOKEN.
    const errMsg = err instanceof Error ? err.message : String(err);
    console.error("/v1/fill-body error:", errMsg);
    if (err instanceof ReplicateTimeoutError) {
      res.status(504).json({ error: "model_timeout" });
      return;
    }
    // Replicate rate-limits (low balance, burst exceeded, etc.) bubble up
    // as 429s. Propagate them so the client's existing rateLimited handler
    // surfaces "Too many requests. Please wait a moment." instead of the
    // catch-all 500 — much friendlier than "fill_body_failed" in a toast.
    const msg = err instanceof Error ? err.message : String(err);
    if (
      msg.includes("status 429") ||
      msg.includes("Too Many Requests") ||
      msg.toLowerCase().includes("throttled")
    ) {
      res.status(429).json({ error: "rate_limited" });
      return;
    }
    res.status(500).json({ error: "fill_body_failed" });
  }
}

function wireMapping(mapping: FillBodyMapping) {
  return {
    canvas_width: mapping.canvasWidth,
    canvas_height: mapping.canvasHeight,
    original_x: mapping.originalX,
    original_y: mapping.originalY,
    original_width: mapping.originalWidth,
    original_height: mapping.originalHeight,
  };
}

function wireEdges(edges: FillBodyEdges) {
  return {
    left: edges.left,
    right: edges.right,
    bottom: edges.bottom,
  };
}
