import type { VercelRequest, VercelResponse } from "@vercel/node";
import { supabase } from "../../../lib/supabase.js";

const APP_SCHEME = process.env.APP_URL_SCHEME ?? "aaavatar";

/**
 * POST /v1/account/resend-magic-link
 *
 * Triggered by the in-app "Sync across Macs" banner that appears on devices
 * that paid via the pre-auth checkout flow. Sends a Supabase magic-link
 * email to the address on file (the `device_grants` → `auth.users.email`),
 * which when clicked deep-links back into the app and signs the user in.
 *
 * The endpoint is anonymous-friendly — it authenticates by matching the
 * `X-Device-Fingerprint` header against the device_grants table. We
 * deliberately do NOT accept a free-form email in the body: that would let
 * any caller spam arbitrary inboxes via our SMTP. Tying the email to a
 * paid device grant means each device can only resend a link to its own
 * paying user.
 *
 * Returns:
 *   200 { sent: true }
 *   400 { error: "missing_device_fingerprint" }
 *   404 { error: "no_grant_for_device" }      — caller is not a paid device
 *   500 { error: "send_failed" }
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const fingerprint = req.headers["x-device-fingerprint"];
  if (typeof fingerprint !== "string" || !fingerprint) {
    res.status(400).json({ error: "missing_device_fingerprint" });
    return;
  }

  try {
    const { data: grant } = await supabase
      .from("device_grants")
      .select("user_id")
      .eq("device_fingerprint", fingerprint)
      .maybeSingle();
    const userId = (grant?.user_id as string | undefined) ?? null;
    if (!userId) {
      res.status(404).json({ error: "no_grant_for_device" });
      return;
    }

    // GoTrue admin API — direct `supabase.schema("auth").from("users")`
    // queries are blocked by PostgREST (PGRST106); service role bypasses
    // RLS but not the schema gate.
    const { data: userData, error: userErr } = await supabase.auth.admin.getUserById(userId);
    if (userErr) throw userErr;
    const email = userData.user?.email ?? null;
    if (!email) {
      res.status(404).json({ error: "no_grant_for_device" });
      return;
    }

    // signInWithOtp triggers Supabase's templated magic-link email. The
    // email is already confirmed (set by `findOrCreateUserByEmail` in the
    // webhook), so shouldCreateUser:false is safe.
    const { error: sendErr } = await supabase.auth.signInWithOtp({
      email,
      options: {
        shouldCreateUser: false,
        emailRedirectTo: `${APP_SCHEME}://auth-callback`,
      },
    });
    if (sendErr) throw sendErr;

    res.status(200).json({ sent: true, email });
  } catch (err) {
    console.error("/v1/account/resend-magic-link error", err);
    res.status(500).json({ error: "send_failed" });
  }
}
