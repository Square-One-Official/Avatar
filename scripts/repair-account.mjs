// One-shot recovery for accounts whose Stripe webhook silently failed
// (PGRST106 / "Invalid schema: auth"). Re-runs the webhook side-effects
// idempotently from the latest active Stripe subscription on the email.
//
// Usage: node scripts/repair-account.mjs <email> [--apply]
//   Without --apply it's a dry run; with --apply the writes go through.
import { createClient } from "../backend/node_modules/@supabase/supabase-js/dist/index.mjs";
import Stripe from "../backend/node_modules/stripe/esm/stripe.esm.node.js";
import fs from "node:fs";

function loadEnv(rel) {
  const text = fs.readFileSync(new URL(rel, import.meta.url), "utf8");
  const out = {};
  let i = 0;
  while (i < text.length) {
    const eol = text.indexOf("\n", i);
    const lineEnd = eol === -1 ? text.length : eol;
    const line = text.slice(i, lineEnd);
    if (!line || line.startsWith("#") || !line.includes("=")) { i = lineEnd + 1; continue; }
    const eq = line.indexOf("=");
    const key = line.slice(0, eq).trim();
    let val = line.slice(eq + 1);
    if (val.startsWith('"')) {
      val = val.slice(1);
      const close = text.indexOf('"', i + eq + 2);
      if (close === -1) { out[key] = val; break; }
      val = text.slice(i + eq + 2, close);
      i = close + 2;
      out[key] = val;
      continue;
    }
    out[key] = val.trim();
    i = lineEnd + 1;
  }
  return out;
}
const localEnv = loadEnv("../backend/.env.local");
const prodEnv = loadEnv("../backend/.env.production.tmp");
const env = { ...localEnv, ...prodEnv, SUPABASE_URL: localEnv.SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY: localEnv.SUPABASE_SERVICE_ROLE_KEY };

const supa = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
const stripe = new Stripe(env.STRIPE_SECRET_KEY);
const email = process.argv[2];
const apply = process.argv.includes("--apply");
if (!email) { console.error("usage: repair-account.mjs <email> [--apply]"); process.exit(1); }
console.log(apply ? "MODE: APPLY (writes will happen)" : "MODE: DRY RUN");

// 1. Find the Supabase user.
async function findUserIdByEmail(target) {
  const t = target.toLowerCase();
  for (let page = 1; ; page++) {
    const { data, error } = await supa.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    const hit = data.users.find((u) => u.email?.toLowerCase() === t);
    if (hit) return hit.id;
    if (data.users.length < 200) return null;
  }
}
const userId = await findUserIdByEmail(email);
if (!userId) { console.error("No supabase user for", email); process.exit(1); }
console.log("Supabase user:", userId);

// 2. Find the most-recent ACTIVE subscription on Stripe for this email.
const customers = await stripe.customers.list({ email, limit: 10 });
let chosenSub = null;
let chosenCustomer = null;
for (const c of customers.data) {
  const ss = await stripe.subscriptions.list({ customer: c.id, status: "all", limit: 5 });
  for (const s of ss.data) {
    if (s.status === "active" || s.status === "trialing") {
      if (!chosenSub || s.created > chosenSub.created) {
        chosenSub = s;
        chosenCustomer = c;
      }
    }
  }
}
if (!chosenSub) { console.error("No active subscription found on Stripe for", email); process.exit(1); }
console.log("Active subscription:", chosenSub.id, "on customer", chosenCustomer.id);
console.log("  price:", chosenSub.items.data[0]?.price?.id);
console.log("  current_period_end:", new Date(chosenSub.current_period_end * 1000).toISOString());
console.log("  metadata:", chosenSub.metadata);

// 3. Resolve tier + interval from the subscription metadata. Vercel env
// pull blanks "Sensitive" vars, so the price-id mapping isn't reachable
// from the script — but `subscribe-anonymous.ts` writes both fields into
// `subscription_data.metadata`, which Stripe carries on the resulting
// subscription. That's the source we trust here.
const tier = chosenSub.metadata?.tier;
const interval = chosenSub.metadata?.interval;
if (!["starter", "plus", "studio", "pro"].includes(tier)) {
  console.error("Unrecognized tier in subscription metadata:", tier); process.exit(1);
}
if (!["month", "year"].includes(interval)) {
  console.error("Unrecognized interval in subscription metadata:", interval); process.exit(1);
}
const monthlyCredits = { starter: 20, plus: 50, studio: 150, pro: 200 }[tier];

// 4. Pull the most recent paid invoice on this subscription for credit grant ref.
const invoices = await stripe.invoices.list({ subscription: chosenSub.id, limit: 5 });
const paidInvoice = invoices.data.find((inv) => inv.status === "paid");
if (!paidInvoice) { console.error("No paid invoice for subscription"); process.exit(1); }
console.log("Paid invoice:", paidInvoice.id);

const ref = interval === "year" ? `${paidInvoice.id}:0` : paidInvoice.id;
const fingerprint = chosenSub.metadata?.device_fingerprint || null;

console.log("\n=== PLAN ===");
console.log(`1. users.stripe_customer_id := ${chosenCustomer.id}`);
console.log(`2. subscriptions UPSERT (id=${chosenSub.id}, status=${chosenSub.status}, tier=${tier})`);
if (fingerprint) console.log(`3. device_grants UPSERT (fingerprint=${fingerprint})`);
else console.log("3. (skip device_grants — no fingerprint in metadata)");
console.log(`4. credit_ledger INSERT (delta=+${monthlyCredits}, reason=period_renewal, ref=${ref})`);

if (!apply) { console.log("\nDry run done. Re-run with --apply to write."); process.exit(0); }

console.log("\n=== APPLYING ===");
{
  const { error } = await supa.from("users").upsert(
    { id: userId, stripe_customer_id: chosenCustomer.id }, { onConflict: "id" }
  );
  if (error) throw error;
  console.log("✓ users.stripe_customer_id linked");
}
{
  const { error } = await supa.from("subscriptions").upsert(
    {
      id: chosenSub.id,
      user_id: userId,
      tier,
      status: chosenSub.status,
      monthly_credits: monthlyCredits,
      current_period_start: new Date(chosenSub.current_period_start * 1000).toISOString(),
      current_period_end: new Date(chosenSub.current_period_end * 1000).toISOString(),
      cancel_at_period_end: chosenSub.cancel_at_period_end,
    },
    { onConflict: "id" },
  );
  if (error) throw error;
  console.log("✓ subscriptions row upserted");
}
if (fingerprint) {
  const { error } = await supa.from("device_grants").upsert(
    { device_fingerprint: fingerprint, user_id: userId, source: "stripe_checkout" },
    { onConflict: "device_fingerprint" },
  );
  if (error) throw error;
  console.log("✓ device_grants row upserted");
}
{
  const { error } = await supa.from("credit_ledger").insert({
    user_id: userId, delta: monthlyCredits, reason: "period_renewal", ref,
  });
  if (error && !/duplicate key/i.test(error.message)) throw error;
  console.log(error ? "= credit_ledger row already present (idempotent)" : "✓ credit_ledger row inserted");
}
console.log("\nDone.");
