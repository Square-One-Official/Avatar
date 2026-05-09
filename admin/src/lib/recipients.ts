import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL ?? "";
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";

const supabase = url && serviceRoleKey
  ? createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
  : null;

/**
 * Resolves an announcement's `audience` setting to a list of email
 * addresses for the newsletter blast. Pulls users from
 * `auth.users` via the GoTrue admin API — direct queries against the
 * `auth.users` table are blocked by PostgREST's schema gate even with
 * the service role.
 *
 * Cohort definitions:
 *   - all          → every confirmed-email user
 *   - freeUsers    → no active/trialing subscription
 *   - proUsers     → at least one active/trialing subscription
 *   - specificEmails → the explicit list authored on the announcement
 *
 * Caveat: this snapshots the cohort at send time. A user who upgrades
 * after the blast still counts as a free-tier recipient if they were
 * free when we resolved the list.
 */
export async function resolveRecipients(
  audience: "all" | "freeUsers" | "proUsers" | "specificEmails",
  audienceEmails: string[],
): Promise<string[]> {
  if (audience === "specificEmails") {
    return uniqueLowercased(audienceEmails);
  }
  if (!supabase) {
    console.warn("Supabase not configured — recipient resolution returns empty.");
    return [];
  }

  // 1. Pull every confirmed-email user via paginated admin API.
  const allEmails: { id: string; email: string }[] = [];
  for (let page = 1; ; page++) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    for (const u of data.users) {
      if (u.email && u.email_confirmed_at) {
        allEmails.push({ id: u.id, email: u.email.toLowerCase() });
      }
    }
    if (data.users.length < 200) break;
  }
  if (allEmails.length === 0) return [];
  if (audience === "all") return uniqueLowercased(allEmails.map((u) => u.email));

  // 2. Cross-reference subscription state for free vs. pro splits.
  const { data: subs, error: subErr } = await supabase
    .from("subscriptions")
    .select("user_id, status")
    .in("status", ["active", "trialing"]);
  if (subErr) throw subErr;
  const proUserIds = new Set((subs ?? []).map((r: { user_id: string }) => r.user_id));

  if (audience === "proUsers") {
    return uniqueLowercased(allEmails.filter((u) => proUserIds.has(u.id)).map((u) => u.email));
  }
  // freeUsers
  return uniqueLowercased(allEmails.filter((u) => !proUserIds.has(u.id)).map((u) => u.email));
}

function uniqueLowercased(list: string[]): string[] {
  const set = new Set<string>();
  for (const raw of list) {
    const v = (raw ?? "").trim().toLowerCase();
    if (v) set.add(v);
  }
  return Array.from(set);
}
