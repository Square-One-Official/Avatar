import type { VercelRequest, VercelResponse } from "@vercel/node";
import { checkRateLimit, requireUser } from "../../lib/auth.js";
import {
  currentCredits,
  ensureUser,
  freeCutoutsUsed,
  logCredit,
  tryConsumeFreeCutout,
  FREE_CUTOUTS_ALLOWANCE,
} from "../../lib/supabase.js";
import { magicCutout } from "../../lib/replicate.js";

export const config = {
  api: {
    bodyParser: { sizeLimit: "15mb" },
  },
};

/**
 * POST /v1/cutout
 *
 * Body:    { image: <base64 PNG> }
 * Returns: 200 { cutout: <base64 PNG>, credits_remaining: int }
 *          402 { error: "insufficient_credits", credits_remaining: 0 }
 *          401 { error: "unauthorized" }
 *          429 { error: "rate_limited" }
 *
 * Pricing model — credits are tried first, then the free trial:
 *   - User has ≥ 1 credit (subscription grant or topup leftovers): spend
 *     1 credit, logged to credit_ledger.
 *   - Otherwise, free user under FREE_CUTOUTS_ALLOWANCE: claim a trial
 *     slot via the atomic SQL function (no ledger entry).
 *   - Otherwise: 402.
 *
 * This ordering matters: a free user who topped up before the trial was
 * introduced still spends the credits they paid for, not the free slots.
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

  const base64 = (req.body?.image ?? "") as string;
  if (!base64 || typeof base64 !== "string") {
    res.status(400).json({ error: "missing_image" });
    return;
  }

  const cleaned = base64.replace(/^data:image\/[a-z]+;base64,/i, "");
  let inputBytes: Buffer;
  try {
    inputBytes = Buffer.from(cleaned, "base64");
  } catch {
    res.status(400).json({ error: "invalid_base64" });
    return;
  }
  if (inputBytes.length === 0 || inputBytes.length > 12 * 1024 * 1024) {
    res.status(400).json({ error: "image_size_out_of_range" });
    return;
  }

  const devEmails = (process.env.DEV_UNLIMITED_EMAILS ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  const isDevUser = !!user.email && devEmails.includes(user.email.toLowerCase());

  // Spend mode chosen at admit time and reused after the model call so the
  // pre-check and post-deduct stay in sync.
  type SpendMode = "credit" | "free_trial" | "dev";

  try {
    await ensureUser(user.id);

    let mode: SpendMode;
    if (isDevUser) {
      mode = "dev";
    } else {
      const credits = await currentCredits(user.id);
      if (credits >= 1) {
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

    // Replicate accepts either an https URL or a data URL. We send a data URL
    // so we don't have to host the input anywhere intermediate.
    const imageDataUrl = `data:image/png;base64,${inputBytes.toString("base64")}`;
    const resultUrl = await magicCutout({ imageDataUrl });

    const download = await fetch(resultUrl);
    if (!download.ok) {
      throw new Error(`Replicate result fetch failed: ${download.status}`);
    }
    const cutoutBytes = Buffer.from(await download.arrayBuffer());

    // Deduct only after we have the bytes in hand.
    if (mode === "credit") {
      await logCredit({
        userId: user.id,
        delta: -1,
        reason: "magic_cutout",
        ref: resultUrl,
      });
    } else if (mode === "free_trial") {
      // Atomic conditional UPDATE — under contention only the first
      // FREE_CUTOUTS_ALLOWANCE concurrent calls increment. A null return
      // means a race lost; the user still gets the cutout we already
      // paid Replicate for, same shape of best-effort accounting we accept
      // on the Pro credit side.
      await tryConsumeFreeCutout(user.id);
    }

    const creditsRemaining =
      mode === "dev" ? 999 : await currentCredits(user.id);
    res.status(200).json({
      cutout: cutoutBytes.toString("base64"),
      credits_remaining: creditsRemaining,
    });
  } catch (err) {
    console.error("/v1/cutout error", err);
    res.status(500).json({ error: "cutout_failed" });
  }
}
