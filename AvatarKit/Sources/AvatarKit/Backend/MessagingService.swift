import Foundation
import Observation

/// In-app berichten-queue (E17.3) — opvolger van de losse announcement-calls.
/// Haalt de server-getargete `/v1/messages`, houdt een queue bij, en beheert
/// dismiss-state zowel lokaal (UserDefaults, los van v1) als server-side
/// (gedeelde announcement_seen via `markMessageSeen`). Targeting/schedule
/// worden server-side toegepast; de client dedupliceert op lokaal-gedismisste
/// slugs zodat een bericht binnen dezelfde sessie niet terugkeert.
@MainActor
@Observable
public final class MessagingService {
    public private(set) var queue: [Message] = []
    public var current: Message? { queue.first }

    private let backend: BackendClient
    private let defaults: UserDefaults
    private static let dismissedKey = "messaging.dismissedSlugs"

    public init(backend: BackendClient, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
    }

    /// Vernieuw de queue vanaf de server, met lokaal-gedismisste slugs eruit
    /// gefilterd. Faalt stil (berichten zijn niet-kritisch).
    public func refresh() async {
        guard let fetched = try? await backend.fetchMessages() else { return }
        queue = Self.filterDismissed(fetched, dismissed: dismissedSlugs())
    }

    /// Dismiss een bericht: lokaal onthouden, uit de queue halen, en
    /// server-side markeren (fire-and-forget; faalt stil).
    public func dismiss(_ message: Message, action: String = "dismiss") {
        var d = dismissedSlugs()
        d.insert(message.slug)
        persist(d)
        queue.removeAll { $0.slug == message.slug }
        Task { try? await backend.markMessageSeen(slug: message.slug, action: action) }
    }

    /// CTA-tap telt ook als gezien (zelfde server-actie als v1).
    public func acknowledge(_ message: Message) {
        dismiss(message, action: "cta")
    }

    /// Pure filter — testbaar zonder netwerk.
    public static func filterDismissed(_ messages: [Message], dismissed: Set<String>) -> [Message] {
        messages.filter { !dismissed.contains($0.slug) }
    }

    #if DEBUG
    /// Smoke-run-haak (E17.5): injecteer een test-bericht zodat het sheet
    /// zonder backend/CMS verschijnt.
    public func debugInject(_ message: Message) {
        queue = [message]
    }
    #endif

    private func dismissedSlugs() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.dismissedKey) ?? [])
    }

    private func persist(_ slugs: Set<String>) {
        defaults.set(Array(slugs), forKey: Self.dismissedKey)
    }
}
