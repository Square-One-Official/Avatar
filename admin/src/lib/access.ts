import type { PayloadRequest } from "payload";

/**
 * Shared "authenticated principal" access rule — the single source of truth for
 * every collection whose access is "must be a resolved user".
 *
 * Authorized iff Payload has resolved `req.user`: either an admin session cookie
 * OR a VALID `Authorization: users API-Key <key>` (the backend's read path —
 * Payload validates the key and sets `req.user` before access runs). Crucially
 * it does NOT trust the mere PRESENCE of an Authorization header; a bogus key
 * leaves `req.user` null and is denied.
 *
 * This exists because the original read-access bypass propagated across
 * collections by copy-paste (the old Effects comment read "Mirrors
 * BadgeComponents…", carrying along a `|| Boolean(req.headers.get(
 * "authorization"))` clause that authorized any header value). Funnelling the
 * rule through one definition means a new collection imports the correct
 * predicate instead of copying a neighbor, so that bypass can't reappear.
 */
// Concrete `boolean` return (not the broader `Access` result) so this is
// assignable to every access slot — including the `admin` panel-access field,
// which, unlike read/create/update/delete, cannot return a `Where` query.
export const authed = ({ req }: { req: PayloadRequest }): boolean => Boolean(req.user);
