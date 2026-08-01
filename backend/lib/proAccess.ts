/**
 * E14.9 — the Pro list, resolved from the CMS.
 *
 * Historically the only non-Stripe route to Pro was `DEV_UNLIMITED_EMAILS`:
 * a comma-separated env var on this project, requiring a redeploy to change
 * and offering exactly one setting (skip every credit check). The CMS
 * collection `pro-access` (admin/src/collections/ProAccess.ts) replaces it as
 * the primary source and adds the level we actually wanted for non-dev
 * accounts — a comped subscription that still spends credits.
 *
 * Two levels:
 *   - "pro"       comped subscription. Pro gates open; credits are granted
 *                 monthly (see `ensureCompedCredits` in supabase.ts) and spent
 *                 normally, so a comped account has a bounded Replicate bill.
 *   - "unlimited" the old env-var behaviour. Every credit check bypassed, plus
 *                 the Advanced model picker (`is_dev_unlimited`, E15.5).
 *
 * `DEV_UNLIMITED_EMAILS` stays live as a break-glass fallback: an address in
 * the env var is always "unlimited", regardless of the CMS. It's the way back
 * in when the CMS is unreachable and the one place that doesn't depend on
 * another deployable being healthy.
 *
 * Failure policy: entitlements fail CLOSED (a CMS outage must not hand Pro to
 * everyone), but not abruptly — a failed refresh keeps serving the last known
 * good list for up to `STALE_TTL_MS` so a 30-second CMS blip doesn't yank Pro
 * out from under a comped user mid-edit.
 */

const PAYLOAD_API_URL = process.env.PAYLOAD_API_URL ?? "";
const PAYLOAD_API_KEY = process.env.PAYLOAD_API_KEY ?? "";

export type ProAccessMode = "pro" | "unlimited";

export type ProOverride = {
  /** Which level of access this address was granted. */
  mode: ProAccessMode;
  /** Credits granted per calendar month. Meaningless for "unlimited". */
  monthlyCredits: number;
  /** Where the grant came from — surfaces in logs when a grant is disputed. */
  source: "cms" | "env";
};

type ProAccessEntry = {
  email: string;
  mode: ProAccessMode;
  monthlyCredits: number;
  active: boolean;
  expiresAt: string | null;
};

/** Same normalisation as `payloadBase()` in payload.ts — kept local so this
 *  module can be reasoned about (and unit-tested) on its own. */
function payloadBase(): string | null {
  let u = PAYLOAD_API_URL.trim().replace(/\/+$/, "");
  if (!u) return null;
  if (!/^https?:\/\//i.test(u)) u = `https://${u}`;
  try {
    const parsed = new URL(u);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return null;
    return u;
  } catch {
    return null;
  }
}

// 60 s fresh window, mirroring the announcement/effect caches — a CMS edit
// takes effect within a minute. On a failed refresh the same entries keep
// being served until STALE_TTL_MS, after which we fall back to env-only.
const CACHE_TTL_MS = 60_000;
const STALE_TTL_MS = 10 * 60_000;

let cache: { fetchedAt: number; entries: ProAccessEntry[] } | null = null;
let inFlight: Promise<ProAccessEntry[]> | null = null;

async function loadProAccessList(): Promise<ProAccessEntry[]> {
  const now = Date.now();
  if (cache && now - cache.fetchedAt < CACHE_TTL_MS) return cache.entries;

  // Collapse concurrent refreshes on a warm instance into one round-trip.
  if (inFlight) return inFlight;

  inFlight = (async () => {
    const base = payloadBase();
    if (!base || !PAYLOAD_API_KEY) {
      console.warn("PAYLOAD_API_URL invalid / PAYLOAD_API_KEY missing — CMS pro-list disabled");
      return [];
    }

    const url = new URL(`${base}/pro-access`);
    url.searchParams.set("limit", "500");
    url.searchParams.set("depth", "0");
    url.searchParams.set("where[active][equals]", "true");

    const res = await fetch(url, {
      headers: {
        Authorization: `users API-Key ${PAYLOAD_API_KEY}`,
        Accept: "application/json",
      },
    });
    if (!res.ok) {
      throw new Error(`pro-access fetch failed: ${res.status} ${await res.text().catch(() => "")}`);
    }

    const json = (await res.json()) as { docs?: unknown[] };
    const docs = Array.isArray(json.docs) ? json.docs : [];
    return docs.map(normalize).filter((e): e is ProAccessEntry => e !== null);
  })()
    .then((entries) => {
      cache = { fetchedAt: Date.now(), entries };
      return entries;
    })
    .catch((err) => {
      console.error("[pro-access] refresh failed", err);
      // Serve the last known good list while it's within the stale window;
      // past that, deny (env-var fallback still applies at the caller).
      if (cache && Date.now() - cache.fetchedAt < STALE_TTL_MS) {
        console.warn("[pro-access] serving stale list");
        return cache.entries;
      }
      return [];
    })
    .finally(() => {
      inFlight = null;
    });

  return inFlight;
}

function normalize(raw: unknown): ProAccessEntry | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;

  const email = typeof r.email === "string" ? r.email.trim().toLowerCase() : "";
  if (!email) return null;

  const mode: ProAccessMode = r.access === "unlimited" ? "unlimited" : "pro";

  // Payload serialises `number` fields as numbers, but the column is numeric
  // and a hand-edited row could arrive as a string — coerce defensively so a
  // bad value degrades to the default rather than NaN-ing the grant maths.
  const rawCredits = typeof r.monthlyCredits === "string" ? Number(r.monthlyCredits) : r.monthlyCredits;
  const monthlyCredits =
    typeof rawCredits === "number" && Number.isFinite(rawCredits) && rawCredits >= 0
      ? Math.floor(rawCredits)
      : 200;

  return {
    email,
    mode,
    monthlyCredits,
    // `active: false` is already filtered server-side; re-checked here so a
    // future query change can't silently widen the list.
    active: r.active !== false,
    expiresAt: typeof r.expiresAt === "string" ? r.expiresAt : null,
  };
}

/** Emails hard-coded in the environment. Always "unlimited" — this is the
 *  break-glass path, so it deliberately doesn't depend on the CMS. */
function envUnlimitedEmails(): string[] {
  return (process.env.DEV_UNLIMITED_EMAILS ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
}

/**
 * Resolve the non-Stripe entitlement for a signed-in address, or null when
 * the account has to pay like everyone else.
 *
 * Never throws: a CMS failure resolves to the env-var answer.
 */
export async function proOverrideFor(
  email: string | null | undefined,
): Promise<ProOverride | null> {
  if (!email) return null;
  const needle = email.trim().toLowerCase();
  if (!needle) return null;

  if (envUnlimitedEmails().includes(needle)) {
    return { mode: "unlimited", monthlyCredits: 0, source: "env" };
  }

  const entries = await loadProAccessList();
  const hit = entries.find((e) => e.email === needle);
  if (!hit || !hit.active) return null;
  if (hit.expiresAt && new Date(hit.expiresAt) <= new Date()) return null;

  return { mode: hit.mode, monthlyCredits: hit.monthlyCredits, source: "cms" };
}

/** True for the internal/dev level only — the one that skips credit accounting
 *  entirely. Drop-in async replacement for the old `isDevUnlimitedUser`. */
export async function isUnlimitedUser(email: string | null | undefined): Promise<boolean> {
  return (await proOverrideFor(email))?.mode === "unlimited";
}

/** Test seam — drops the cached list so a following call refetches. */
export function __resetProAccessCache(): void {
  cache = null;
  inFlight = null;
}
