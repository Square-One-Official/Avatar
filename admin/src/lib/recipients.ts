import { Pool } from "pg";

/**
 * Newsletter cohort resolution (audit HIGH #12). Replaces the previous
 * implementation that called `supabase.auth.admin.listUsers()` with the
 * service role key — which meant a compromise of the admin app could
 * enumerate every account email in the database.
 *
 * The new flow reads from the `public.newsletter_cohorts` materialised
 * view, owned by the migration runner and refreshed via a SECURITY
 * DEFINER function. The admin's scoped `payload_app` role gets only
 * `SELECT` on the view and `EXECUTE` on the refresh function — it never
 * sees `auth.users` directly. See `backend/sql/010_newsletter_cohorts_view.sql`.
 */

const connectionString =
  process.env.PAYLOAD_DATABASE_URL ??
  process.env.DATABASE_URL ??
  process.env.POSTGRES_URL_NON_POOLING ??
  "";

// One small pool per warm function instance. Two connections is more
// than enough — newsletter sends are infrequent and serialised, and the
// admin's hot path (Payload's own UI traffic) uses its own pool.
const pool = connectionString
  ? new Pool({ connectionString, max: 2 })
  : null;

/**
 * Resolves an announcement's `audience` setting to a list of email
 * addresses for the newsletter blast. Always refreshes the materialised
 * view first so the cohort reflects the latest signups + tier changes.
 *
 * Cohorts:
 *   - all          → every confirmed-email user
 *   - freeUsers    → no active/trialing subscription
 *   - proUsers     → at least one active/trialing subscription
 *   - specificEmails → the explicit list authored on the announcement
 */
export async function resolveRecipients(
  audience: "all" | "freeUsers" | "proUsers" | "specificEmails",
  audienceEmails: string[],
): Promise<string[]> {
  if (audience === "specificEmails") {
    return uniqueLowercased(audienceEmails);
  }
  if (!pool) {
    console.warn(
      "PAYLOAD_DATABASE_URL not configured — recipient resolution returns empty",
    );
    return [];
  }

  // Refresh first so a brand-new user who confirmed their email between
  // the last newsletter and now is included. The function is SECURITY
  // DEFINER so the call runs as the migration role — payload_app itself
  // has no privileges on auth.users.
  await pool.query("select public.refresh_newsletter_cohorts()");

  let rows: { email: string }[];
  if (audience === "all") {
    const result = await pool.query<{ email: string }>(
      "select email from public.newsletter_cohorts",
    );
    rows = result.rows;
  } else {
    const tier = audience === "proUsers" ? "pro" : "free";
    const result = await pool.query<{ email: string }>(
      "select email from public.newsletter_cohorts where tier = $1",
      [tier],
    );
    rows = result.rows;
  }
  return uniqueLowercased(rows.map((r) => r.email));
}

function uniqueLowercased(list: string[]): string[] {
  const set = new Set<string>();
  for (const raw of list) {
    const v = (raw ?? "").trim().toLowerCase();
    if (v) set.add(v);
  }
  return Array.from(set);
}
