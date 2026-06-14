/**
 * Thin Payload-CMS REST client used by the announcement endpoints.
 *
 * The CMS (admin.aaavatar.nl) is the source of truth for announcement
 * content. The backend reads it via Payload's auto-generated REST API and
 * caches the result for a short window so the macOS-app sign-in path
 * doesn't pay a cross-region round-trip on every call.
 *
 * Auth: a Payload "API Keys" user (created in Payload's Users collection
 * with `enableAPIKey: true`) — the backend sends `Authorization: users
 * API-Key <key>` and Payload skips its session/cookie checks.
 */
const PAYLOAD_API_URL = process.env.PAYLOAD_API_URL ?? "";
const PAYLOAD_API_KEY = process.env.PAYLOAD_API_KEY ?? "";

/** What the backend needs from one Payload announcement document. */
export type PayloadAnnouncement = {
  slug: string;
  title: string;
  body: string;
  imageUrl: string | null;
  cta: { label: string; url: string } | null;
  frequency: "once" | "everySignInUntilDismissed" | "untilDate" | "delayedNthSignIn";
  untilDate: string | null;
  delayN: number | null;
  audience: "all" | "freeUsers" | "proUsers" | "specificEmails";
  audienceEmails: string[];
  minAppVersion: string | null;
  publishedAt: string | null;
  expiresAt: string | null;
  badgeTargets: { componentId: string; durationDays: number }[];
  newsletter: {
    send: boolean;
    sentAt: string | null;
  } | null;
};

type CacheEntry = {
  expiresAt: number;
  payload: PayloadAnnouncement[];
};

/**
 * 60-second in-process cache. Vercel functions are short-lived but a single
 * warm instance can serve dozens of /pending calls back-to-back during a
 * sign-in spike (e.g. after a release announcement goes live). Avoiding
 * the Payload round-trip on each one keeps p95 well under 200 ms.
 */
let cache: CacheEntry | null = null;
const CACHE_TTL_MS = 60_000;

export async function fetchPublishedAnnouncements(): Promise<PayloadAnnouncement[]> {
  const now = Date.now();
  if (cache && cache.expiresAt > now) {
    return cache.payload;
  }

  if (!PAYLOAD_API_URL || !PAYLOAD_API_KEY) {
    // Misconfigured → return empty so the macOS app never sees a 500 on a
    // path that's only loosely critical.
    console.warn("PAYLOAD_API_URL / PAYLOAD_API_KEY missing — announcements disabled");
    return [];
  }

  // Fetch published, non-expired announcements. Payload uses the `where`
  // querystring with bracketed operators.
  const url = new URL(`${PAYLOAD_API_URL.replace(/\/$/, "")}/announcements`);
  url.searchParams.set("limit", "100");
  url.searchParams.set("depth", "1");
  url.searchParams.set("where[publishedAt][exists]", "true");
  url.searchParams.set("where[publishedAt][less_than_equal]", new Date().toISOString());

  const res = await fetch(url, {
    headers: {
      Authorization: `users API-Key ${PAYLOAD_API_KEY}`,
      Accept: "application/json",
    },
  });
  if (!res.ok) {
    console.error("Payload fetch failed", res.status, await res.text().catch(() => ""));
    return [];
  }

  const json = (await res.json()) as { docs?: unknown[] };
  const docs = Array.isArray(json.docs) ? json.docs : [];
  const announcements = docs.map(normalize).filter((a): a is PayloadAnnouncement => a !== null);

  cache = { expiresAt: now + CACHE_TTL_MS, payload: announcements };
  return announcements;
}

/**
 * Coerce a Payload document (loosely typed JSON) into the shape the
 * backend consumes. Payload nests upload references as `{ url, ... }`
 * objects when `depth>=1`; richText fields ship as a Lexical AST that we
 * flatten to a Markdown-ish string here so the macOS client can render it
 * with `AttributedString(markdown:)`.
 */
function normalize(raw: unknown): PayloadAnnouncement | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;

  const slug = typeof r.slug === "string" ? r.slug : null;
  const title = typeof r.title === "string" ? r.title : null;
  if (!slug || !title) return null;

  const image = r.image as { url?: string } | null | undefined;
  const imageUrl = image && typeof image.url === "string" ? image.url : null;

  const cta = (() => {
    const c = r.primaryCta as { label?: string; url?: string } | null | undefined;
    if (!c || typeof c.label !== "string" || typeof c.url !== "string") return null;
    if (!c.label.trim() || !c.url.trim()) return null;
    return { label: c.label, url: c.url };
  })();

  const frequency = (() => {
    const f = r.frequency;
    if (
      f === "once" ||
      f === "everySignInUntilDismissed" ||
      f === "untilDate" ||
      f === "delayedNthSignIn"
    ) {
      return f;
    }
    return "once";
  })();

  const audience = (() => {
    const a = r.audience;
    if (a === "all" || a === "freeUsers" || a === "proUsers" || a === "specificEmails") {
      return a;
    }
    return "all";
  })();

  const audienceEmails = Array.isArray(r.audienceEmails)
    ? (r.audienceEmails as unknown[])
        .map((e) => (typeof e === "object" && e !== null ? (e as { email?: string }).email : e))
        .filter((e): e is string => typeof e === "string" && e.trim().length > 0)
        .map((e) => e.trim().toLowerCase())
    : [];

  const badgeTargets = Array.isArray(r.badgeTargets)
    ? (r.badgeTargets as unknown[])
        .map((b) => {
          if (typeof b !== "object" || b === null) return null;
          const o = b as { componentId?: unknown; durationDays?: unknown };
          if (typeof o.componentId !== "string") return null;
          const days = typeof o.durationDays === "number" ? o.durationDays : 14;
          return { componentId: o.componentId, durationDays: days };
        })
        .filter((b): b is { componentId: string; durationDays: number } => b !== null)
    : [];

  const newsletter = (() => {
    const n = r.newsletter as
      | { send?: unknown; sentAt?: unknown }
      | null
      | undefined;
    if (!n || typeof n !== "object") return null;
    return {
      send: n.send === true,
      sentAt: typeof n.sentAt === "string" ? n.sentAt : null,
    };
  })();

  return {
    slug,
    title,
    body: lexicalToMarkdown(r.body),
    imageUrl,
    cta,
    frequency,
    untilDate: typeof r.untilDate === "string" ? r.untilDate : null,
    delayN: typeof r.delayN === "number" ? r.delayN : null,
    audience,
    audienceEmails,
    minAppVersion: typeof r.minAppVersion === "string" ? r.minAppVersion : null,
    publishedAt: typeof r.publishedAt === "string" ? r.publishedAt : null,
    expiresAt: typeof r.expiresAt === "string" ? r.expiresAt : null,
    badgeTargets,
    newsletter,
  };
}

/**
 * Walk a Lexical rich-text AST and emit Markdown. Covers the node types
 * used in the announcement body — paragraph, heading, list, list-item,
 * link, bold/italic. Unknown nodes contribute their text content without
 * formatting so a future schema change degrades gracefully instead of
 * blanking the body.
 */
function lexicalToMarkdown(raw: unknown): string {
  if (typeof raw === "string") return raw;
  if (typeof raw !== "object" || raw === null) return "";
  const root = (raw as { root?: { children?: unknown[] } }).root;
  const children = Array.isArray(root?.children) ? root!.children! : [];
  return children.map(renderNode).join("\n\n").trim();
}

function renderNode(node: unknown): string {
  if (typeof node !== "object" || node === null) return "";
  const n = node as { type?: string; tag?: string; text?: string; format?: number; url?: string; children?: unknown[]; listType?: string };

  if (n.type === "text" && typeof n.text === "string") {
    let t = n.text;
    const fmt = typeof n.format === "number" ? n.format : 0;
    if (fmt & 1) t = `**${t}**`;     // bold
    if (fmt & 2) t = `*${t}*`;       // italic
    if (fmt & 4) t = `~~${t}~~`;     // strikethrough
    if (fmt & 16) t = `\`${t}\``;    // code
    return t;
  }

  const inner = (n.children ?? []).map(renderNode).join("");
  switch (n.type) {
    case "paragraph": return inner;
    case "heading":   return `${"#".repeat(headingLevel(n.tag))} ${inner}`;
    case "link":      return `[${inner}](${n.url ?? ""})`;
    case "list":      return inner;
    case "listitem": {
      const bullet = n.listType === "number" ? "1." : "-";
      return `${bullet} ${inner}`;
    }
    case "linebreak": return "\n";
    default:          return inner;
  }
}

function headingLevel(tag: string | undefined): number {
  if (!tag) return 2;
  const m = tag.match(/^h([1-6])$/);
  return m ? Number(m[1]) : 2;
}

/**
 * Records a newsletter unsubscribe in Payload's `newsletter-unsubscribes`
 * collection (audit HIGH #15). Idempotent — the collection has a unique
 * index on `email`, so re-clicking a stale link is a no-op. Returns true
 * when the row was created OR already existed (i.e. the user is now
 * opted-out); false on configuration / transport failure.
 */
export async function recordNewsletterUnsubscribe(
  email: string,
  source: "one_click" | "list_unsubscribe_post" | "manual" = "one_click",
): Promise<boolean> {
  if (!PAYLOAD_API_URL || !PAYLOAD_API_KEY) {
    console.warn("PAYLOAD_API_URL / PAYLOAD_API_KEY missing — unsubscribe NOT recorded");
    return false;
  }

  const url = `${PAYLOAD_API_URL.replace(/\/$/, "")}/newsletter-unsubscribes`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `users API-Key ${PAYLOAD_API_KEY}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({ email: email.trim().toLowerCase(), source }),
  });

  if (res.ok) return true;

  // The unique index makes a second click return 400 with a Postgres
  // duplicate-key error wrapped in Payload's error envelope. Treat it as
  // success — the user is opted out either way.
  if (res.status === 400) {
    const text = await res.text().catch(() => "");
    if (/duplicate|unique/i.test(text)) return true;
    console.warn("unsubscribe POST 400 (not duplicate)", text);
    return false;
  }
  console.error("unsubscribe POST failed", res.status, await res.text().catch(() => ""));
  return false;
}

// ---------------------------------------------------------------------------
// E17.2 — Messages (verenigd model, slug "messages"). Naast de announcement-
// functies hierboven; niet-destructief. Spiegelt admin/src/collections/
// Messages.ts: kanaal + targeting-group + schedule-group + body/image/cta.
// ---------------------------------------------------------------------------

export type PayloadMessage = {
  slug: string;
  title: string;
  channel: "inApp" | "email" | "both";
  body: string;
  imageUrl: string | null;
  cta: { label: string; url: string } | null;
  // schedule (flat)
  frequency: "once" | "everySignInUntilDismissed" | "untilDate" | "delayedNthSignIn";
  untilDate: string | null;
  delayN: number | null;
  publishedAt: string | null;
  expiresAt: string | null;
  // targeting (flat)
  cohort: "all" | "freeUsers" | "proUsers" | "specificEmails";
  audienceEmails: string[];
  signupAfter: string | null;
  signupBefore: string | null;
  minAppVersion: string | null;
  platform: "all" | "macos";
};

let messageCache: { expiresAt: number; payload: PayloadMessage[] } | null = null;

export async function fetchPublishedMessages(): Promise<PayloadMessage[]> {
  const now = Date.now();
  if (messageCache && messageCache.expiresAt > now) {
    return messageCache.payload;
  }
  if (!PAYLOAD_API_URL || !PAYLOAD_API_KEY) {
    console.warn("PAYLOAD_API_URL / PAYLOAD_API_KEY missing — messages disabled");
    return [];
  }

  const url = new URL(`${PAYLOAD_API_URL.replace(/\/$/, "")}/messages`);
  url.searchParams.set("limit", "100");
  url.searchParams.set("depth", "1");
  // publishedAt leeft onder de schedule-group → dot-notation in de where.
  url.searchParams.set("where[schedule.publishedAt][exists]", "true");
  url.searchParams.set("where[schedule.publishedAt][less_than_equal]", new Date().toISOString());

  const res = await fetch(url, {
    headers: { Authorization: `users API-Key ${PAYLOAD_API_KEY}`, Accept: "application/json" },
  });
  if (!res.ok) {
    console.error("Payload messages fetch failed", res.status, await res.text().catch(() => ""));
    return [];
  }
  const json = (await res.json()) as { docs?: unknown[] };
  const docs = Array.isArray(json.docs) ? json.docs : [];
  const messages = docs.map(normalizeMessage).filter((m): m is PayloadMessage => m !== null);
  messageCache = { expiresAt: now + CACHE_TTL_MS, payload: messages };
  return messages;
}

function normalizeMessage(raw: unknown): PayloadMessage | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  const slug = typeof r.slug === "string" ? r.slug : null;
  const title = typeof r.title === "string" ? r.title : null;
  if (!slug || !title) return null;

  const channel = (() => {
    const c = r.channel;
    return c === "inApp" || c === "email" || c === "both" ? c : "inApp";
  })();

  const image = r.image as { url?: string } | null | undefined;
  const imageUrl = image && typeof image.url === "string" ? image.url : null;

  const cta = (() => {
    const c = r.primaryCta as { label?: string; url?: string } | null | undefined;
    if (!c || typeof c.label !== "string" || typeof c.url !== "string") return null;
    if (!c.label.trim() || !c.url.trim()) return null;
    return { label: c.label, url: c.url };
  })();

  const schedule = (r.schedule as Record<string, unknown>) ?? {};
  const frequency = (() => {
    const f = schedule.frequency;
    if (f === "once" || f === "everySignInUntilDismissed" || f === "untilDate" || f === "delayedNthSignIn") return f;
    return "once";
  })();

  const targeting = (r.targeting as Record<string, unknown>) ?? {};
  const cohort = (() => {
    const a = targeting.cohort;
    if (a === "all" || a === "freeUsers" || a === "proUsers" || a === "specificEmails") return a;
    return "all";
  })();
  const audienceEmails = Array.isArray(targeting.audienceEmails)
    ? (targeting.audienceEmails as unknown[])
        .map((e) => (typeof e === "object" && e !== null ? (e as { email?: string }).email : e))
        .filter((e): e is string => typeof e === "string" && e.trim().length > 0)
        .map((e) => e.trim().toLowerCase())
    : [];
  const platform = targeting.platform === "macos" ? "macos" : "all";

  const str = (v: unknown): string | null => (typeof v === "string" ? v : null);

  return {
    slug,
    title,
    channel,
    body: lexicalToMarkdown(r.body),
    imageUrl,
    cta,
    frequency,
    untilDate: str(schedule.untilDate),
    delayN: typeof schedule.delayN === "number" ? schedule.delayN : null,
    publishedAt: str(schedule.publishedAt),
    expiresAt: str(schedule.expiresAt),
    cohort,
    audienceEmails,
    signupAfter: str(targeting.signupAfter),
    signupBefore: str(targeting.signupBefore),
    minAppVersion: str(targeting.minAppVersion),
    platform,
  };
}

/**
 * Best-effort semver compare — returns true if `version >= min`. Falls
 * back to "true" on anything unparseable so a typo in `minAppVersion`
 * never blocks an announcement entirely.
 */
export function meetsMinVersion(version: string | null, min: string | null): boolean {
  if (!min) return true;
  if (!version) return false;
  const parse = (s: string) => s.split(".").map((p) => parseInt(p, 10) || 0);
  const v = parse(version);
  const m = parse(min);
  for (let i = 0; i < Math.max(v.length, m.length); i++) {
    const a = v[i] ?? 0;
    const b = m[i] ?? 0;
    if (a > b) return true;
    if (a < b) return false;
  }
  return true;
}
