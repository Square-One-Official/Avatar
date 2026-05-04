// Scan Stripe for active subscriptions whose Supabase mirror is missing
// or stale. Symptoms of the 2026-05-04 webhook outage: customer paid,
// `subscriptions` row never written, `device_grants` row missing.
//
// Read-only. Lists candidates so you can decide who to repair.
//
// Usage: node scripts/audit-affected-accounts.mjs [--since-hours 48]
import { createClient } from "../backend/node_modules/@supabase/supabase-js/dist/index.mjs";
import Stripe from "../backend/node_modules/stripe/esm/stripe.esm.node.js";
import fs from "node:fs";

function loadEnv(rel) {
  const text = fs.readFileSync(new URL(rel, import.meta.url), "utf8");
  const out = {}; let i = 0;
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
      i = close + 2; out[key] = val; continue;
    }
    out[key] = val.trim(); i = lineEnd + 1;
  }
  return out;
}
const localEnv = loadEnv("../backend/.env.local");
const prodEnv = loadEnv("../backend/.env.production.tmp");
const env = { ...localEnv, STRIPE_SECRET_KEY: prodEnv.STRIPE_SECRET_KEY };
const supa = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
const stripe = new Stripe(env.STRIPE_SECRET_KEY);

const sinceArg = process.argv.indexOf("--since-hours");
const sinceHours = sinceArg >= 0 ? parseInt(process.argv[sinceArg + 1], 10) : 168; // default 7d
const sinceTs = Math.floor(Date.now() / 1000) - sinceHours * 3600;
console.log(`Scanning Stripe subscriptions created in the last ${sinceHours}h…\n`);

// Iterate all subscriptions created since cutoff. Stripe paginates 100/page.
const affected = [];
let starting_after = undefined;
let scanned = 0;
for (;;) {
  const page = await stripe.subscriptions.list({
    status: "all", limit: 100, created: { gte: sinceTs },
    ...(starting_after ? { starting_after } : {}),
  });
  for (const sub of page.data) {
    scanned++;
    if (sub.status !== "active" && sub.status !== "trialing") continue;
    const customerId = typeof sub.customer === "string" ? sub.customer : sub.customer.id;
    // Read-back: is there a matching subscriptions row?
    const { data: row } = await supa.from("subscriptions").select("id, status").eq("id", sub.id).maybeSingle();
    if (row) continue; // healthy
    // Resolve customer email for the report.
    let email = null;
    try {
      const c = await stripe.customers.retrieve(customerId);
      if (!c.deleted) email = c.email;
    } catch {}
    affected.push({
      sub: sub.id, status: sub.status, customer: customerId, email,
      flow: sub.metadata?.flow, fingerprint: sub.metadata?.device_fingerprint,
      created: new Date(sub.created * 1000).toISOString(),
    });
  }
  if (!page.has_more) break;
  starting_after = page.data[page.data.length - 1].id;
}

console.log(`Scanned ${scanned} subscriptions.`);
if (affected.length === 0) {
  console.log("✅ No drift detected — every active Stripe subscription has a matching Supabase row.");
} else {
  console.log(`\n⚠️  ${affected.length} active Stripe subscription(s) without a Supabase row:\n`);
  for (const a of affected) console.log(a);
  console.log("\nRepair each with:  node scripts/repair-account.mjs <email> --apply");
}
