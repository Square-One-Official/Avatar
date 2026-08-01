import { fileURLToPath } from "node:url";
import path from "node:path";
import { makeAppcastHandler } from "../lib/appcastFeed.js";

/**
 * GET /appcast-v2.xml  (rewrite in vercel.json → /api/appcast-v2)
 *
 * Sparkle-feed voor Aaavatar 2 (E13.1) — eigen kanaal naast /appcast.xml
 * zodat v1-installs (die op het oude feed-URL gepind staan) 2.0-releases
 * nooit aangeboden krijgen. Zelfde trust-root-keuze als appcast.ts:
 * geserveerd vanaf api.aaavatar.nl (TLS-gepind in de app) i.p.v. GitHub raw.
 * `_appcast-v2.xml` wordt door scripts/release-v2.sh in lockstep gehouden
 * met de canon in de repo-root.
 */

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export default makeAppcastHandler(path.join(__dirname, "_appcast-v2.xml"));
