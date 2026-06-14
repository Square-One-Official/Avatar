/**
 * Lifecycle-campagnes (E17.7) — welkom → tips → launch, gevoed door het
 * verenigde Message-model. Eén getypeerde bron die zowel een seed-script als
 * een cron-dispatch kan consumeren (zie admin/LIFECYCLE-CAMPAGNES.md).
 *
 * Elke stap stuurt `sendAfterDays` na signup naar het cohort; dat vertaalt
 * naar een `targeting.signupAfter/Before`-venster op het Message-record, zodat
 * de bestaande `/v1/messages`-feed + sendNewsletter-dispatch het zonder extra
 * logica oppikken. Niet-destructief: dit creëert Message-records, het raakt
 * Announcements niet.
 */

export type LifecycleStep = {
  /** Stabiele slug-prefix; de seed maakt unieke slugs per run/datum. */
  slug: string;
  title: string;
  /** Markdown body (Lexical wordt bij seed uit deze tekst gebouwd). */
  body: string;
  channel: "inApp" | "email" | "both";
  cohort: "all" | "freeUsers" | "proUsers" | "specificEmails";
  /** Dagen na signup dat deze stap relevant wordt. */
  sendAfterDays: number;
  /** Vensterbreedte in dagen (signupBefore = signupAfter + window). */
  windowDays: number;
  cta?: { label: string; url: string };
};

export const lifecycleCampaign: LifecycleStep[] = [
  {
    slug: "lifecycle-welcome",
    title: "Welcome to Aaavatar",
    body: "You're in! Drop a photo and we'll cut out a clean portrait in seconds — background gone, edges sharp.",
    channel: "both",
    cohort: "all",
    sendAfterDays: 0,
    windowDays: 1,
    cta: { label: "Make your first portrait", url: "aaavatar://import" },
  },
  {
    slug: "lifecycle-tips",
    title: "3 things you can do next",
    body: "**Effects** restyle a portrait, **Hair** & **Clothing** edit just one thing, and **Backgrounds** drop in a brand colour. All non-destructive.",
    channel: "both",
    cohort: "all",
    sendAfterDays: 2,
    windowDays: 2,
    cta: { label: "Explore the editor", url: "aaavatar://effects" },
  },
  {
    slug: "lifecycle-launch",
    title: "Go Pro — unlimited portraits & cloud edits",
    body: "Loving it? Pro unlocks unlimited portraits, every cloud edit and 200 credits a month.",
    channel: "both",
    cohort: "freeUsers",
    sendAfterDays: 7,
    windowDays: 7,
    cta: { label: "See Pro", url: "aaavatar://paywall" },
  },
];

/**
 * Vertaalt een stap + een ankerdatum (doorgaans "nu", de seed-/cron-run)
 * naar een create-payload voor de Payload `messages`-collectie. De
 * signup-window richt de stap op accounts van de juiste leeftijd.
 */
export function toMessageDraft(step: LifecycleStep, now: Date = new Date()) {
  const signupBefore = new Date(now.getTime() - step.sendAfterDays * 86_400_000);
  const signupAfter = new Date(signupBefore.getTime() - step.windowDays * 86_400_000);
  return {
    slug: `${step.slug}-${signupBefore.toISOString().slice(0, 10)}`,
    title: step.title,
    channel: step.channel,
    body: step.body,
    primaryCta: step.cta ? { label: step.cta.label, url: step.cta.url } : undefined,
    targeting: {
      cohort: step.cohort,
      signupAfter: signupAfter.toISOString(),
      signupBefore: signupBefore.toISOString(),
      platform: "all" as const,
    },
    schedule: {
      frequency: "once" as const,
      publishedAt: now.toISOString(),
    },
  };
}
