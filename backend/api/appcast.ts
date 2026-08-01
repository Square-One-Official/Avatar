import { fileURLToPath } from "node:url";
import path from "node:path";
import { makeAppcastHandler } from "../lib/appcastFeed.js";

/**
 * GET /appcast.xml  (rewritten in vercel.json → /api/appcast)
 *
 * Sparkle feed for the macOS app (v1), served from infrastructure we control
 * (audit HIGH #10). Previously the feed lived at
 *   https://raw.githubusercontent.com/Square-One-Official/Avatar/main/appcast.xml
 * which means GitHub holds the trust root for our update channel — a
 * compromised GitHub account or a BGP-hijack of `raw.githubusercontent.com`
 * could push a malicious appcast to every install. Sparkle's per-item
 * EdDSA signature catches a tampered DMG, but the appcast itself was
 * trusted-by-host. Serving it from `api.aaavatar.nl` re-anchors the
 * trust root to the same domain that already authenticates Avatar's
 * other backend calls (now with TLS pinning — see TLSPinning.swift).
 *
 * The canonical `appcast.xml` still lives at the repo root and continues
 * to be served by GitHub raw so older builds (which have the GitHub
 * SUFeedURL baked in) keep receiving updates during the transition. New
 * builds point at api.aaavatar.nl/appcast.xml.
 *
 * E13.1: de serveer-logica (cache/etag/304) is gedeeld met het
 * Aaavatar 2-kanaal (/appcast-v2.xml) via lib/appcastFeed.ts.
 */

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export default makeAppcastHandler(path.join(__dirname, "_appcast.xml"));
