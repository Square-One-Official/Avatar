import { fileURLToPath } from "node:url";
import path from "node:path";
import { makeAppcastHandler } from "../lib/appcastFeed.js";

/**
 * GET /appcast.xml  (rewritten in vercel.json → /api/appcast)
 *
 * Sparkle feed for the macOS v1 app, served from infrastructure we control
 * (audit HIGH #10). Previously the feed lived at
 *   https://raw.githubusercontent.com/thierrzz/Avatar/main/appcast.xml
 * Serving it from `api.aaavatar.nl` re-anchors the trust root to the same
 * domain that already authenticates Avatar's other backend calls (now with
 * TLS pinning — see TLSPinning.swift).
 *
 * Aaavatar 2 uses `/appcast-v2.xml` (see appcast-v2.ts) so a 2.0 release
 * can never be offered to a v1 install.
 */

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export default makeAppcastHandler(path.join(__dirname, "_appcast.xml"));
