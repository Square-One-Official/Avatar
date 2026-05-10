import type { Endpoint, PayloadHandler } from "payload";
import { Resend } from "resend";
import { render } from "@react-email/render";
import * as React from "react";
import AnnouncementEmail from "../emails/AnnouncementEmail.js";
import { lexicalToHtml } from "../lib/lexical.js";
import { resolveRecipients } from "../lib/recipients.js";

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
    collection: "announcements",
    id: announcementId,
    depth: 2,
  });
  if (!ann) {
    return Response.json({ error: "Announcement not found" }, { status: 404 });
  }
  const newsletter = (ann as Record<string, unknown>).newsletter as
    | { send?: boolean; subject?: string; fromName?: string; customBody?: unknown; sentAt?: string }
    | undefined;
  if (!newsletter?.send && !testMode) {
    return Response.json({ error: "newsletter.send is false" }, { status: 400 });
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

  const html = await render(
    React.createElement(AnnouncementEmail, {
      title,
      bodyHtml,
      imageUrl,
      cta,
      unsubscribeUrl: undefined, // Wire up before any non-test bulk send.
    }),
  );

  const subject = newsletter?.subject?.trim() || title;
  const fromName = newsletter?.fromName?.trim() || process.env.RESEND_FROM_NAME || "Aaavatar";
  const fromEmail = process.env.RESEND_FROM_EMAIL || "news@aaavatar.nl";
  const from = `${fromName} <${fromEmail}>`;

  const resend = new Resend(apiKey);

  if (testMode) {
    const { data, error } = await resend.emails.send({
      from,
      to: testEmail,
      subject: `[TEST] ${subject}`,
      html,
    });
    if (error) {
      return Response.json({ error: error.message }, { status: 500 });
    }
    return Response.json({ ok: true, testMessageId: data?.id });
  }

  // Resolve audience.
  const audience = ((ann as { audience?: string }).audience ?? "all") as
    | "all"
    | "freeUsers"
    | "proUsers"
    | "specificEmails";
  const audienceEmails = (() => {
    const arr = (ann as { audienceEmails?: { email?: string }[] }).audienceEmails ?? [];
    return arr.map((e) => e.email ?? "").filter(Boolean);
  })();
  const recipients = await resolveRecipients(audience, audienceEmails);
  if (recipients.length === 0) {
    return Response.json({ error: "No recipients matched" }, { status: 400 });
  }

  // Batch through Resend's bulk-send API. Each call accepts up to 100
  // emails; we use 50 to leave headroom for retries.
  const BATCH = 50;
  const batches: { from: string; to: string; subject: string; html: string }[][] = [];
  for (let i = 0; i < recipients.length; i += BATCH) {
    const slice = recipients.slice(i, i + BATCH);
    batches.push(slice.map((to) => ({ from, to, subject, html })));
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
    collection: "announcements",
    id: announcementId,
    data: {
      newsletter: {
        ...newsletter,
        send: true,
        sentAt: new Date().toISOString(),
      },
    },
  });

  return Response.json({ ok: true, sent, batches: batches.length });
};

export const sendNewsletterEndpoint: Endpoint = {
  path: "/send-newsletter",
  method: "post",
  handler,
};
