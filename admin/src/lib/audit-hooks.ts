import type {
  CollectionAfterChangeHook,
  CollectionAfterDeleteHook,
} from "payload";

/**
 * Audit-log hook factory (audit MEDIUM #24). Drop the returned pair into
 * a collection's `hooks` config and every create / update / delete on
 * that collection writes an immutable row in the `audit-log` collection.
 *
 *   import { auditHooks } from "../lib/audit-hooks";
 *   ...
 *   hooks: {
 *     afterChange: [auditHooks("announcements").afterChange],
 *     afterDelete: [auditHooks("announcements").afterDelete],
 *   }
 *
 * The `summary` argument is a function that picks a short, low-cardinality
 * tag from the document (typically title, slug, or email) — we never
 * store full diffs or anything that could leak secrets via the log itself.
 *
 * Hook errors are swallowed and logged: failing to write to the audit
 * log must NEVER block the primary operation. A user's announcement
 * save can't depend on the audit collection being healthy.
 */
export function auditHooks<T = Record<string, unknown>>(
  collection: string,
  summary: (doc: T) => string,
): { afterChange: CollectionAfterChangeHook; afterDelete: CollectionAfterDeleteHook } {
  return {
    afterChange: async ({ doc, req, operation }) => {
      try {
        await req.payload.create({
          collection: "audit-log",
          data: {
            at: new Date().toISOString(),
            action: operation === "create" ? "created" : "updated",
            collection,
            docId: stringifyDocId((doc as { id?: unknown }).id),
            summary: clip(summary(doc as T)),
            actor: numericActorId(req.user),
            actorEmail: (req.user as { email?: string } | null | undefined)?.email ?? null,
          },
        });
      } catch (err) {
        console.error(`[audit-log] ${collection} afterChange write failed`, err);
      }
      return doc;
    },

    afterDelete: async ({ doc, req }) => {
      try {
        await req.payload.create({
          collection: "audit-log",
          data: {
            at: new Date().toISOString(),
            action: "deleted",
            collection,
            docId: stringifyDocId((doc as { id?: unknown }).id),
            summary: clip(summary(doc as T)),
            actor: numericActorId(req.user),
            actorEmail: (req.user as { email?: string } | null | undefined)?.email ?? null,
          },
        });
      } catch (err) {
        console.error(`[audit-log] ${collection} afterDelete write failed`, err);
      }
      return doc;
    },
  };
}

function stringifyDocId(id: unknown): string {
  if (typeof id === "string") return id;
  if (typeof id === "number") return String(id);
  return "";
}

/**
 * De `actor`-relatie in de audit-log-collectie is een users-relationship —
 * in de gegenereerde types (postgres) een numeriek id. Alles wat geen number
 * is wordt null: een string-id had de integer-FK-insert toch al laten falen,
 * dus dit verandert geen werkend runtime-gedrag.
 */
function numericActorId(user: unknown): number | null {
  const id = (user as { id?: unknown } | null | undefined)?.id;
  return typeof id === "number" ? id : null;
}

/**
 * Cap the summary at 160 chars. The summary is meant to be a tag, not a
 * description — anything longer is the caller passing the wrong field.
 */
function clip(s: string): string {
  if (typeof s !== "string") return "";
  const trimmed = s.trim();
  return trimmed.length > 160 ? trimmed.slice(0, 157) + "…" : trimmed;
}
