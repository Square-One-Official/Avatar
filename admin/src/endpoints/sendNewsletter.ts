import type { Endpoint, Payload, PayloadHandler } from "payload";
import { Resend } from "resend";
import { render } from "@react-email/render";
import * as React from "react";
import AnnouncementEmail from "../emails/AnnouncementEmail";
import MessageEmail from "../emails/MessageEmail";
import { lexicalToHtml } from "../lib/lexical";
import { resolveRecipients } from "../lib/recipients";
import { unsubscribeUrlFor } from "../lib/unsubscribe-token";

/**
 * POST /api/send-newsletter
 *
 * Body: { announcementId: string, testMode?: boolean, testEmail?: string }
 *
 *   - testMode + testEmail → renders the email and sends ONLY to the test
 *     address. Doesn't stamp `newsletter.sentAt`. Use this before a real
 *     blast.
 *   - production mode → resolves the audience, batches the recipient list
 *     into Resend's bulk-send API (max 50 per call), then stamps
 *     `newsletter.sentAt` so re-firing the endpoint is a no-op.
 *
 * Auth: Payload-authenticated only. Hit it from the admin UI via a
 * button on the Announcement edit screen.
 */
const handler: PayloadHandler = async (req) => {
  if (!req.user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await req.json?.()) ?? {};
  const announcementId = typeof body.announcementId === "string" ? body.announcementId : "";
  const testMode = body.testMode === true;
  const testEmail = typeof body.testEmail === "string" ? body.testEmail : "";
  // E17.6: hetzelfde endpoint dient nu ook het verenigde Message-model.
  // Default blijft "announcements" zodat de bestaande knop ongewijzigd werkt.
  const collection: "announcements" | "messages" =
    body.collection === "messages" ? "messages" : "announcements";

  if (!announcementId) {
    return Response.json({ error: "announcementId required" }, { status: 400 });
  }
  if (testMode && !testEmail) {
    return Response.json({ error: "testEmail required in testMode" }, { status: 400 });
  }

  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    return Response.json({ error: "RESEND_API_KEY not set" }, { status: 500 });
  }

  const ann = await req.payload.findByID({
    collection,
    id: announcementId,
    depth: 2,
  });
  if (!ann) {
    return Response.json({ error: "Record not found" }, { status: 404 });
  }
  const newsletter = (ann as Record<string, unknown>).newsletter as
    | { send?: boolean; subject?: string; fromName?: string; customBody?: unknown; sentAt?: string }
    | undefined;
  // Send-gate: announcements op newsletter.send; messages op channel email/both.
  const channel = (ann as { channel?: string }).channel;
  const sendEnabled =
    collection === "messages"
      ? channel === "email" || channel === "both"
      : newsletter?.send === true;
  if (!sendEnabled && !testMode) {
    return Response.json(
      { error: collection === "messages" ? "channel is not email/both" : "newsletter.send is false" },
      { status: 400 },
    );
  }
  if (newsletter?.sentAt && !testMode) {
    return Response.json({ error: "Already sent at " + newsletter.sentAt }, { status: 409 });
  }

  // Build the email HTML.
  const title = (ann as { title?: string }).title ?? "Update";
  const image = (ann as { image?: { url?: string } | null }).image;
  const imageUrl = image?.url ?? null;
  const cta = (() => {
    const c = (ann as { primaryCta?: { label?: string; url?: string } }).primaryCta;
    if (!c?.label || !c?.url) return null;
    return { label: c.label, url: c.url };
  })();
  const bodySource = newsletter?.customBody ?? (ann as { body?: unknown }).body;
  const bodyHtml = lexicalToHtml(bodySource);

  // Helper: render the email body with this recipient's unsubscribe URL
  // baked in. Doing it per-recipient is the only way to keep the link
  // bound to the specific address — Resend's `batch.send` accepts an
  // array of distinct messages, so the per-recipient cost is just an HMAC
  // + a `render()` call (both cheap; the JSX tree is tiny).
  // E17.6: messages krijgen het v2-merk-template; announcements het oude.
  const EmailTemplate = collection === "messages" ? MessageEmail : AnnouncementEmail;
  const renderForRecipient = async (recipient: string): Promise<string> =>
    render(
      React.createElement(EmailTemplate, {
        title,
        bodyHtml,
        imageUrl,
        cta,
        unsubscribeUrl: unsubscribeUrlFor(recipient),
      }),
    );

  const subject = newsletter?.subject?.trim() || title;
  const fromName = newsletter?.fromName?.trim() || process.env.RESEND_FROM_NAME || "Aaavatar";
  const fromEmail = process.env.RESEND_FROM_EMAIL || "news@aaavatar.nl";
  const from = `${fromName} <${fromEmail}>`;

  const resend = new Resend(apiKey);

  if (testMode) {
    const testHtml = await renderForRecipient(testEmail);
    const testUnsubscribeUrl = unsubscribeUrlFor(testEmail);
    const { data, error } = await resend.emails.send({
      from,
      to: testEmail,
      subject: `[TEST] ${subject}`,
      html: testHtml,
      headers: listUnsubscribeHeaders(testUnsubscribeUrl),
    });
    if (error) {
      return Response.json({ error: error.message }, { status: 500 });
    }
    return Response.json({ ok: true, testMessageId: data?.id });
  }

  // Resolve audience. Announcements dragen `audience` top-level; messages
  // dragen het onder `targeting.cohort` (zelfde waarden).
  const targeting = (ann as { targeting?: { cohort?: string; audienceEmails?: { email?: string }[] } }).targeting;
  const audience = (
    collection === "messages"
      ? targeting?.cohort ?? "all"
      : (ann as { audience?: string }).audience ?? "all"
  ) as "all" | "freeUsers" | "proUsers" | "specificEmails";
  const audienceEmails = (() => {
    const arr =
      collection === "messages"
        ? targeting?.audienceEmails ?? []
        : (ann as { audienceEmails?: { email?: string }[] }).audienceEmails ?? [];
    return arr.map((e) => e.email ?? "").filter(Boolean);
  })();
  const cohort = await resolveRecipients(audience, audienceEmails);

  // GDPR Art. 21 / CAN-SPAM: anyone who clicked unsubscribe in a previous
  // newsletter must be filtered out of every audience before send. The
  // Payload `newsletter-unsubscribes` collection is the source of truth;
  // we pull every row (it's small — at most "every user who's ever
  // opted out") and exclude their emails from the cohort.
  const optOut = await fetchUnsubscribedEmails(req.payload);
  const recipients = cohort.filter((e) => !optOut.has(e.toLowerCase()));
  const skippedOptOut = cohort.length - recipients.length;
  if (recipients.length === 0) {
    return Response.json(
      {
        error: skippedOptOut > 0
          ? "All matched users have unsubscribed from the newsletter"
          : "No recipients matched",
      },
      { status: 400 },
    );
  }

  // Batch through Resend's bulk-send API. Each call accepts up to 100
  // emails; we use 50 to leave headroom for retries.
  const BATCH = 50;
  type Message = {
    from: string;
    to: string;
    subject: string;
    html: string;
    headers: Record<string, string>;
  };
  const batches: Message[][] = [];
  for (let i = 0; i < recipients.length; i += BATCH) {
    const slice = recipients.slice(i, i + BATCH);
    const rendered = await Promise.all(slice.map(async (to) => {
      const url = unsubscribeUrlFor(to);
      return {
        from,
        to,
        subject,
        html: await renderForRecipient(to),
        headers: listUnsubscribeHeaders(url),
      };
    }));
    batches.push(rendered);
  }

  let sent = 0;
  for (const batch of batches) {
    const { error } = await resend.batch.send(batch);
    if (error) {
      console.error("resend.batch.send error", error);
      // Stop on first batch failure to avoid double-sending on retry. The
      // partial sent count is reported back so the operator knows where
      // to resume manually.
      return Response.json(
        { error: `Resend batch failed after ${sent} sends: ${error.message}` },
        { status: 502 },
      );
    }
    sent += batch.length;
  }

  // Stamp sentAt so the endpoint can't double-fire.
  await req.payload.update({
    collection,
    id: announcementId,
    data: {
      newsletter: {
        ...newsletter,
        send: true,
        sentAt: new Date().toISOString(),
      },
    },
  });

  return Response.json({ ok: true, sent, batches: batches.length, skippedOptOut });
};

/**
 * RFC 8058 + RFC 2369: the `List-Unsubscribe` header is the
 * URL-and-mailto form; `List-Unsubscribe-Post` opts the message into
 * Gmail / Outlook's one-click button by promising the URL accepts a
 * bodyless POST. Our /v1/unsubscribe endpoint handles both GET (link
 * click) and POST (one-click) shapes.
 */
function listUnsubscribeHeaders(url: string): Record<string, string> {
  return {
    "List-Unsubscribe": `<${url}>, <mailto:news@aaavatar.nl?subject=unsubscribe>`,
    "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
  };
}

/**
 * Pull every recorded unsubscribe via Payload's local API and return a
 * lowercased Set for O(1) cohort filtering. The collection is bounded
 * (one row per opted-out address ever), so paginating once with a large
 * limit is fine for the foreseeable future.
 */
async function fetchUnsubscribedEmails(payload: Payload): Promise<Set<string>> {
  const set = new Set<string>();
  try {
    const result = await payload.find({
      collection: "newsletter-unsubscribes",
      limit: 10_000,
      pagination: false,
      depth: 0,
    });
    for (const doc of result.docs ?? []) {
      const email = (doc as { email?: unknown }).email;
      if (typeof email === "string") set.add(email.trim().toLowerCase());
    }
  } catch (err) {
    // Fail-closed would block all sends on a flake. Fail-open is the
    // honest trade-off: we log loudly so the operator catches it.
    console.error("fetchUnsubscribedEmails failed — filter skipped", err);
  }
  return set;
}

export const sendNewsletterEndpoint: Endpoint = {
  path: "/send-newsletter",
  method: "post",
  handler,
};
