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

/**
 * Stricter sibling of `authed`: an interactive admin session only — an
 * API-key principal is denied.
 *
 * `authed` deliberately accepts the backend's `users API-Key <key>` because
 * the backend has to READ content collections. That's fine for announcements
 * and effects, but not for a collection that hands out paid entitlements: it
 * would mean the API key sitting in the avatars-api environment can grant
 * itself Pro. Read stays on `authed` (the backend must read the list); every
 * write goes through this rule, so a leaked API key is read-only against
 * `pro-access`.
 *
 * Payload tags the resolved principal with the strategy that authenticated it
 * (`payload/dist/auth/strategies/apiKey.js` sets `_strategy = "api-key"`; the
 * cookie/JWT strategy sets `"local-jwt"`), which is the only place the two are
 * distinguishable at access-control time.
 */
export const adminSession = ({ req }: { req: PayloadRequest }): boolean => {
  const user = req.user as ({ _strategy?: string } & Record<string, unknown>) | null | undefined;
  if (!user) return false;
  return user._strategy !== "api-key";
};
