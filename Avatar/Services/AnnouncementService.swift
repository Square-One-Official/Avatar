import Foundation
import SwiftUI

/// Fetches feature announcements from the backend, tracks which one is
/// currently being displayed, and exposes "is this component badged?"
/// lookups for the `.newBadge(...)` view modifier.
///
/// Owns no UI of its own — `MainWindow` binds `current` to a `.sheet()`
/// and individual views read `isBadgeActive(for:)`. Calls into
/// `BackendClient` so all auth/transport concerns flow through the same
/// place that serves `/v1/account` and friends.
@MainActor
@Observable
final class AnnouncementService {
    /// The announcement currently being shown to the user. Set to non-nil
    /// after a successful `fetchPending()` returns a hit; cleared when the
    /// user dismisses the sheet (which also POSTs `seen`).
    var current: Announcement?

    /// Map of componentId → expiry. A badge is "active" when its expiry
    /// is in the future and the matching announcement hasn't been
    /// dismissed (the server already filters dismissed ones out).
    private(set) var activeBadges: [String: Date] = [:]

    private unowned let backend: BackendClient

    init(backend: BackendClient) {
        self.backend = backend
    }

    /// Pulls the next pending announcement from the backend. Silent on
    /// errors — a network blip or CMS outage shouldn't surface as an
    /// in-app warning. Re-fetching is cheap (60 s server-side cache), so
    /// the call sites can wire it to multiple lifecycle events without
    /// thinking about deduping.
    func fetchPending() async {
        do {
            let next = try await backend.fetchPendingAnnouncement()
            // Don't clobber an actively-displayed announcement on a
            // background refresh. `current` is the source of truth for
            // "is the modal up right now"; updating it would either pop
            // a different sheet on top or drop the user mid-read.
            if current == nil {
                current = next
            }
        } catch {
            // Soft-fail. Keep whatever was previously cached.
        }
    }

    /// Marks the current (or a specific) announcement seen and clears the
    /// modal state. Call this from the sheet's dismiss handler regardless
    /// of how the user closed it; the server-side upsert is idempotent.
    func dismiss(_ announcement: Announcement, action: DismissAction) async {
        if current?.slug == announcement.slug { current = nil }
        // Drop any badges tied to the slug optimistically so the UI feels
        // responsive — server-side state will catch up on next /badges
        // call. We don't have the announcement → componentId mapping
        // client-side, so we re-fetch instead.
        await refreshBadges()
        do {
            try await backend.markAnnouncementSeen(slug: announcement.slug, action: action.rawValue)
        } catch {
            // Best-effort. If the POST fails, the next /pending call
            // would just re-show the announcement; the user can dismiss
            // again and it'll likely succeed.
        }
    }

    enum DismissAction: String {
        case dismissed
        case ctaClicked = "cta_clicked"
    }

    /// Pulls the active-badges list from the backend and rebuilds the
    /// in-memory map. Drops expired entries on the client too, defensive
    /// against drift between server and client clocks.
    func refreshBadges() async {
        do {
            let fresh = try await backend.fetchBadges()
            let now = Date()
            activeBadges = fresh
                .filter { $0.expiresAt > now }
                .reduce(into: [:]) { acc, b in acc[b.componentId] = b.expiresAt }
        } catch {
            // Soft-fail: keep prior map.
        }
    }

    /// Whether the registered component should currently render a "NEW"
    /// pill. Cheap dictionary lookup; safe to call from a view body.
    func isBadgeActive(for componentId: String) -> Bool {
        guard let expires = activeBadges[componentId] else { return false }
        return expires > Date()
    }
}

/// Canonical list of components that may be badged. Adding a new entry
/// here is step 1 of "I want to spotlight a new button" — step 2 is
/// adding the matching `componentId` row in Payload's badge-component
/// registry so it appears in the admin dropdown, and step 3 is wiring
/// `.newBadge(BadgeComponent.x)` on the relevant view.
///
/// String IDs are deliberately kebab-case because they're shared with
/// the CMS dropdown and embedded in URLs/queries; the enum is only here
/// as a type-safe convenience for app code.
enum BadgeComponent {
    static let magicCutout = "magic-cutout"
    static let fillBody = "fill-body"
    static let colorize = "colorize"
    static let exportSheet = "export-sheet"
    static let backgrounds = "backgrounds"

    /// Features that require cloud AI. NEW pills for these stay hidden
    /// while Privacy mode is Local-only so we don't advertise uploads.
    static let cloudOnlyFeatures: Set<String> = [
        magicCutout, fillBody, colorize
    ]
}
