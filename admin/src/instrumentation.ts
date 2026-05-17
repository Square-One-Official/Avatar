/**
 * Next.js instrumentation hook — runs once when the server boots.
 *
 * We use it to make sure Payload's schema exists in the `payload`
 * Postgres schema before the first request arrives. Payload's
 * `push: true` flag is supposed to do this on adapter init, but in
 * Vercel's serverless cold-start the first inbound request can race
 * the push and observe missing tables ("Failed query: select
 * users.id..."). Awaiting `getPayload({ config })` here guarantees the
 * adapter has fully initialised — including push — before any HTTP
 * handler runs.
 *
 * The check is wrapped in try/catch so a transient DB blip doesn't
 * make the whole instance unusable; the runtime path retries on the
 * next request.
 */
export async function register() {
  if (process.env.NEXT_RUNTIME !== "nodejs") return;

  try {
    // `webpackIgnore: true` tells webpack to leave these as native Node
    // dynamic imports. Without it, the presence of `src/middleware.ts`
    // makes Next.js also compile this file for the Edge runtime, and the
    // Edge build then chokes on Payload's transitive Node-only deps
    // (`payload` → `pg` → `net`, etc.). The runtime guard above keeps
    // these imports unreachable from Edge anyway.
    const [{ getPayload }, configModule] = await Promise.all([
      import(/* webpackIgnore: true */ "payload"),
      import(/* webpackIgnore: true */ "./payload.config.js"),
    ]);
    await getPayload({ config: configModule.default });
    console.log("[instrumentation] Payload initialised — schema synced");
  } catch (err) {
    console.error("[instrumentation] Payload init failed", err);
  }
}
