// Read-only inspection of an account's Pro state.
// Usage: node scripts/inspect-account.mjs <email>
import { createClient } from "../backend/node_modules/@supabase/supabase-js/dist/index.mjs";
import Stripe from "../backend/node_modules/stripe/esm/stripe.esm.node.js";
import fs from "node:fs";

function loadEnv(rel) {
  const text = fs.readFileSync(new URL(rel, import.meta.url), "utf8");
  // Tolerate values wrapped in double-quotes that span newlines (Vercel pull format).
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
      // Find the closing quote, possibly across lines.
      val = val.slice(1);
      const close = text.indexOf('"', i + eq + 2);
      if (close === -1) { out[key] = val; break; }
      val = text.slice(i + eq + 2, close);
      i = close + 2; // past closing quote + newline
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
const env = { ...localEnv, STRIPE_SECRET_KEY: prodEnv.STRIPE_SECRET_KEY };

const supa = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
const stripe = new Stripe(env.STRIPE_SECRET_KEY);
const email = process.argv[2];
if (!email) { console.error("usage: inspect-account.mjs <email>"); process.exit(1); }

console.log("== auth.users ==");
const { data: authUsers, error: authErr } = await supa.auth.admin.listUsers({ perPage: 200 });
if (authErr) throw authErr;
const u = authUsers.users.find((x) => x.email?.toLowerCase() === email.toLowerCase());
console.log(u ? { id: u.id, email: u.email, created_at: u.created_at, last_sign_in_at: u.last_sign_in_at } : "NOT FOUND");
if (!u) process.exit(0);

console.log("\n== public.users ==");
const { data: pubUser } = await supa.from("users").select("*").eq("id", u.id).maybeSingle();
console.log(pubUser);

console.log("\n== subscriptions ==");
const { data: subs } = await supa.from("subscriptions").select("*").eq("user_id", u.id);
console.log(subs);

console.log("\n== device_grants for this user ==");
const { data: grants } = await supa.from("device_grants").select("*").eq("user_id", u.id);
console.log(grants);

console.log("\n== credit_ledger (last 10) ==");
const { data: ledger } = await supa.from("credit_ledger").select("*").eq("user_id", u.id).order("created_at", { ascending: false }).limit(10);
console.log(ledger);

if (pubUser?.stripe_customer_id) {
  console.log("\n== Stripe customer ==");
  const cust = await stripe.customers.retrieve(pubUser.stripe_customer_id);
  console.log({ id: cust.id, email: cust.email, created: new Date(cust.created * 1000).toISOString() });
  console.log("\n== Stripe subscriptions ==");
  const ss = await stripe.subscriptions.list({ customer: pubUser.stripe_customer_id, status: "all", limit: 5 });
  for (const s of ss.data) {
    console.log({
      id: s.id, status: s.status,
      price: s.items.data[0]?.price?.id,
      current_period_end: new Date(s.current_period_end * 1000).toISOString(),
      metadata: s.metadata,
    });
  }
}

// Also try Stripe directly by email — useful when no customer link exists.
console.log("\n== Stripe customers by email ==");
const byEmail = await stripe.customers.list({ email, limit: 5 });
for (const c of byEmail.data) {
  console.log({ id: c.id, email: c.email, created: new Date(c.created * 1000).toISOString() });
  const ss = await stripe.subscriptions.list({ customer: c.id, status: "all", limit: 3 });
  for (const s of ss.data) {
    console.log("  sub", { id: s.id, status: s.status, price: s.items.data[0]?.price?.id, metadata: s.metadata });
  }
  const sessions = await stripe.checkout.sessions.list({ customer: c.id, limit: 5 });
  for (const cs of sessions.data) {
    console.log("  checkout", { id: cs.id, status: cs.status, payment_status: cs.payment_status, mode: cs.mode, metadata: cs.metadata });
  }
}
