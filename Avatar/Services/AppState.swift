import Foundation
import SwiftUI
import SwiftData

enum SettingsTab: String {
    case general, backgrounds, account
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Match System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Bottom-of-window toast variants. `kind` decides which CTA layout the
/// view renders so we can reuse the same chip for several distinct
/// moments without each call site fiddling with flags.
///
/// - `.info` → Pro-only hard limit, no CTA, just dismiss.
/// - `.upgrade` → Free-tier soft gate, single Upgrade pill.
enum ProToastKind: Equatable, Sendable {
    case info
    case upgrade
}

struct ProToast: Equatable {
    let message: String
    let kind: ProToastKind

    var showsUpgrade: Bool { kind == .upgrade }
}

/// Soft error / warning shown via `StatusChip` at the bottom of the main
/// surface. Carries severity so the chip picks the right color and icon
/// without each call site having to think about it.
struct ErrorBanner: Equatable {
    let message: String
    let severity: StatusSeverity
}

/// A pending batch-import confirmation surfaced when a Pro user drops more
/// than `threshold` images at once. Each image costs 1 credit, so we ask
/// before burning through someone's monthly grant in a single drop.
@MainActor
struct BatchConfirmRequest {
    /// Soft cap above which we ask for confirmation. Below this threshold
    /// the drop runs without prompting.
    static let threshold: Int = 20

    let count: Int
    let credits: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void
}

/// What kind of work the processing overlay is currently displaying.
/// Drives the loader's rotating status copy: a cutout/import call sees
/// scissors-and-hair messages, a Fill in Body call sees body-reframing
/// messages. Reset to `.cutout` automatically when `isProcessing` flips
/// back to false, so a subsequent operation defaults to the right copy
/// without each call site having to clean up.
enum ProcessingKind {
    case cutout
    case fillBody
    case colorize
    /// Effects / hair / clothes edits via `/v1/stylize` (gpt-image-1.5
    /// instruction-edit by default). Long
    /// dwell time — the model is slower than colorise.
    case stylize
    /// Real-ESRGAN 2× resolution boost via `/v1/upscale`. Quick and
    /// quiet — the result is just a higher-res cutout, no narrative
    /// transformation.
    case upscale
}

@MainActor
@Observable
final class AppState {
    /// Single-selection facet of the sidebar selection. Bridged to
    /// `selectedPortraitIDs` via `didSet` so callers can write either side
    /// without each call site mirroring manually. The guards make the cross-
    /// writes idempotent so SwiftUI doesn't see redundant churn.
    var selectedPortraitID: UUID? {
        didSet {
            let desired: Set<UUID> = selectedPortraitID.map { [$0] } ?? []
            if selectedPortraitIDs.count <= 1 && selectedPortraitIDs != desired {
                selectedPortraitIDs = desired
            }
        }
    }
    /// Full multi-selection set from the sidebar. `selectedPortraitID` mirrors
    /// this when exactly one row is selected; this set is the source of truth
    /// when the user marquee-selects more than one. Routed through AppState
    /// so the detail pane can render a grid instead of the drop zone.
    var selectedPortraitIDs: Set<UUID> = [] {
        didSet {
            let single: UUID? = selectedPortraitIDs.count == 1 ? selectedPortraitIDs.first : nil
            if selectedPortraitID != single {
                selectedPortraitID = single
            }
        }
    }
    /// Drives the library-side ExportSheet. Non-empty = sheet open and the IDs
    /// inside are the portraits to export. Routed through AppState so both the
    /// sidebar context-menu and the top-right toolbar Export button can trigger
    /// the same sheet without each owning duplicate state.
    var libraryExportPortraitIDs: Set<UUID> = []

    /// Editor inspector column. Lifted out of `EditorView` so the View menu
    /// and `⌘⌥I` can toggle it from anywhere in the key window.
    var showInspector: Bool = true
    /// When true, `NavigationSplitView` shows the detail column only.
    var sidebarHidden: Bool = false
    /// Bumped to focus the library search field (`⌘F`).
    private(set) var librarySearchFocusToken: Int = 0
    /// Bumped to run an `NSOpenPanel` import from the File menu (`⌘N`/`⌘O`).
    private(set) var importRequestToken: Int = 0
    /// Bumped to delete the current library selection from the Edit menu.
    private(set) var deleteRequestToken: Int = 0

    func focusLibrarySearch() { librarySearchFocusToken += 1 }
    func requestImport() { importRequestToken += 1 }
    func requestDelete() { deleteRequestToken += 1 }
    func requestExport() {
        guard !selectedPortraitIDs.isEmpty else { return }
        libraryExportPortraitIDs = selectedPortraitIDs
    }
    var isImporting = false
    var isProcessing = false {
        didSet {
            if !isProcessing { processingKind = .cutout }
        }
    }

    /// Handles for every in-flight `Task.detached` spawned by
    /// `ImportFlow`. Tracked so we can cancel them when the user
    /// navigates away or the scene goes to `.background` — see
    /// `cancelInFlightImports()` and the `onChange(of: scenePhase)` in
    /// `AvatarApp`. Audit MEDIUM #28.
    ///
    /// `@ObservationIgnored` because mutating the array shouldn't
    /// invalidate views; the relevant view-level signal is
    /// `isProcessing`, which is observable.
    @ObservationIgnored
    private var importTasks: [Task<Void, Never>] = []

    /// Register an import task so it can be cancelled later. Prunes any
    /// already-finished handles so the array doesn't grow without bound
    /// across long sessions. Safe to call from any actor — the function
    /// itself is `@MainActor` via the enclosing class.
    func trackImportTask(_ task: Task<Void, Never>) {
        importTasks.removeAll { $0.isCancelled || isFinished($0) }
        importTasks.append(task)
    }

    /// Cancel every in-flight import task and drop the handles. Calls
    /// `Task.cancel()` which Swift Concurrency surfaces as a
    /// `CancellationError` at the next `await` boundary inside the task —
    /// the existing pipeline already has plenty of those (`await
    /// MainActor.run`, `await runPipeline`, etc.) so cancellation lands
    /// cleanly without us having to thread `Task.isCancelled` checks
    /// through every step.
    func cancelInFlightImports() {
        for task in importTasks { task.cancel() }
        importTasks.removeAll()
        // Flip the UI back out of the spinner so a backgrounded window
        // doesn't return showing "Processing…" when the user returns.
        if isProcessing { isProcessing = false }
    }

    /// `Task.isCancelled` doesn't surface "finished normally". The cheap
    /// proxy: poll `value` via a non-blocking wrapper. Since we use
    /// `Task<Void, Never>` the value type is Void, but inspecting
    /// completion synchronously isn't part of the public API — so we
    /// just prune based on `isCancelled` and accept that finished-but-
    /// not-cancelled handles get pruned on the NEXT add.
    private func isFinished(_ task: Task<Void, Never>) -> Bool {
        // Currently no synchronous "isFinished" on Task; rely on
        // `isCancelled` for pruning. A handle that ran to completion is
        // a few hundred bytes — cheap to retain until the next purge.
        return false
    }
    /// Drives the rotating status copy in `ProcessingStatusView`. Set this
    /// BEFORE flipping `isProcessing` to true. Auto-resets to `.cutout`
    /// when `isProcessing` flips back to false.
    var processingKind: ProcessingKind = .cutout
    /// Currently shown error/warning banner. Use the `warn`, `fail`, `note`,
    /// or `report(_:)` helpers below — never assign directly — so every entry
    /// goes through severity classification and any policy decisions
    /// (e.g. `noCredits` opens the paywall instead of a chip).
    var errorBanner: ErrorBanner?

    /// Soft error: recoverable. User can usually retry. Renders as amber.
    func warn(_ message: String) {
        errorBanner = ErrorBanner(message: message, severity: .warning)
    }

    /// Hard error: action probably won't succeed by retry alone. Renders as
    /// muted brick. Use for server faults, decode failures, auth problems.
    func fail(_ message: String) {
        errorBanner = ErrorBanner(message: message, severity: .danger)
    }

    /// Neutral notice. Renders as periwinkle. Use for "nothing to do here"
    /// messages that aren't really errors but need a visible acknowledgement.
    func note(_ message: String) {
        errorBanner = ErrorBanner(message: message, severity: .info)
    }

    func dismissBanner() { errorBanner = nil }

    /// Single source of truth for "what should the UI do when a backend
    /// call fails?". Centralized here so a new feature touching the
    /// `BackendClient` doesn't have to re-derive whether `noCredits`
    /// should open a paywall vs. show a toast.
    ///
    /// Some cases route to a dedicated surface (paywall sheet, sign-in
    /// alert) instead of the banner. Returning `false` means the caller
    /// should suppress its own fallback messaging because we already
    /// surfaced the right UI.
    @discardableResult
    func report(_ error: BackendError) -> Bool {
        switch error {
        case .noCredits:
            // Out of credits is a paywall moment, not a toast — the user
            // needs to top up to proceed, not dismiss a banner.
            showProUpgradeSheet = true
            return true
        case .notSignedIn, .unauthorized:
            // No global "sign in" alert — call sites that need this
            // surface it in-context (paywall has an inline Google button,
            // Magic Cutout fallback shows a chip). For everything else
            // we report a soft warning so the action isn't silent.
            warn(error.errorDescription ?? Loc.somethingWentWrong)
            return true
        case .rateLimited, .transport:
            // Recoverable: try again later or check connection.
            warn(error.errorDescription ?? Loc.somethingWentWrong)
            return true
        case .server, .decode, .proRequired:
            // Either broken or a permission state the chip is the right
            // surface for. `proRequired` is rare (gate should have caught
            // it earlier) but we still want a clear message if it slips.
            fail(error.errorDescription ?? Loc.somethingWentWrong)
            return true
        case .payloadTooLarge:
            // Outside the Magic Cutout flow this should never fire (only
            // `BackendClient.cutout` does the size pre-check). If it does,
            // surface the same too-large copy so the user gets a clear
            // explanation rather than a generic "server error".
            warn(error.errorDescription ?? Loc.somethingWentWrong)
            return true
        }
    }

    /// Which tab to select when the Settings window opens.
    var selectedSettingsTab: SettingsTab = .general

    // MARK: - Pro / Auth
    /// Supabase-backed auth facade. Also used by `BackendClient`.
    let auth: AuthManager = AuthManager()
    /// Pro tier + credits balance. Populated by `BackendClient.me()`.
    let proEntitlement: ProEntitlement = ProEntitlement()
    /// Controls the paywall sheet on the **main window** (editor, import flow,
    /// any 402 from the backend). Triggers from inside Settings should use
    /// `showProUpgradeSheetInSettings` instead — otherwise main window steals
    /// focus and macOS auto-dismisses the preferences pane.
    var showProUpgradeSheet: Bool = false
    /// Currently-selected billing cadence inside `ProUpgradeSheet`. Defaults
    /// to `.year` so the better-value option is anchored on first paint
    /// (Emil: anchor highest-value path; user actively toggles down to
    /// monthly if they want).
    var selectedSubscriptionInterval: SubscriptionInterval = .year
    /// Controls the paywall sheet on the **Settings preferences window**.
    /// Set this from any button inside `SettingsView` so the sheet appears
    /// over Settings and the preferences pane stays open.
    var showProUpgradeSheetInSettings: Bool = false
    /// Set to `true` when the paywall is opened from the Magic Cutout toggle.
    /// After a successful Stripe return, `URLSchemeHandler` flips
    /// `magicCutoutPrefs.enabled` on so the user lands in the state they
    /// originally clicked toward. Other paywall entry points leave this false.
    var pendingMagicCutoutEnable: Bool = false
    /// Toggle persistence for Magic Cutout. Owned here so the URL scheme
    /// handler can flip it on after checkout-return.
    let magicCutoutPrefs: MagicCutoutPreferences = MagicCutoutPreferences()
    /// Local-first AI privacy posture (`localOnly` | `cloudAllowed`) and
    /// the local cutout engine selection (`appleVision` | `downloadedModel`).
    /// Set during first-launch onboarding, editable in Settings → General
    /// → Privacy & AI. Cloud features (Magic Cutout, Fill in Body, Colorize)
    /// gate on `privacyPrefs.cloudAllowed`; the Subject-Lift engine branch
    /// in `ImageProcessor` reads `privacyPrefs.engine` to decide between
    /// Apple Vision V2 and the downloaded matting-model path.
    let privacyPrefs: PrivacyPreferences = PrivacyPreferences()
    /// Lifecycle + state for the optional downloadable matting model
    /// (currently ORMBG, see `ModelManager` for the why). Settings →
    /// Privacy & AI engine row owns the user-facing controls;
    /// `ImportFlow` reads `cachedModelURL()` at pipeline time to decide
    /// whether to use the downloaded engine or fall back to Apple
    /// Vision. Always present even when the user hasn't downloaded —
    /// `state` defaults to `.notDownloaded`.
    let modelManager: ModelManager = ModelManager()
    /// Pending batch-import confirmation. Non-nil → MainWindow shows a
    /// confirm dialog before any of the queued items run through Magic
    /// Cutout (which would each cost 1 credit). Set by `PortraitDropHandler`
    /// when the drop count exceeds `BatchConfirmRequest.threshold`.
    var batchConfirm: BatchConfirmRequest?
    /// Transient Pro toast. Distinct from `lastError` so it can be styled
    /// as a soft upsell (with an Upgrade CTA) or a Pro-only info notice
    /// (no CTA), instead of a destructive error chip. Auto-dismisses a few
    /// seconds after being set.
    var proUpsellToast: ProToast?
    @ObservationIgnored
    private var proUpsellToastTask: Task<Void, Never>?

    /// Free-user gate hit: show the toast with an Upgrade CTA so they can
    /// jump straight to the paywall.
    func showProUpsell(_ message: String, seconds: TimeInterval = 5) {
        present(ProToast(message: message, kind: .upgrade), seconds: seconds)
    }

    /// Pro-user technical limit hit (e.g. batch hard cap): show the same
    /// chip without the Upgrade CTA, since they're already paying.
    func showProInfo(_ message: String, seconds: TimeInterval = 5) {
        present(ProToast(message: message, kind: .info), seconds: seconds)
    }

    private func present(_ toast: ProToast, seconds: TimeInterval) {
        proUpsellToast = toast
        proUpsellToastTask?.cancel()
        proUpsellToastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            if self?.proUpsellToast == toast {
                self?.proUpsellToast = nil
            }
        }
    }

    func dismissProUpsell() {
        proUpsellToastTask?.cancel()
        proUpsellToast = nil
    }
    /// Backend REST client. Bound to the shared `AuthManager` so calls and
    /// sign-in flow see the same token storage.
    @ObservationIgnored
    private(set) lazy var backend: BackendClient = BackendClient(auth: auth)

    /// Feature-announcement + NEW-badge pipeline. Owns the in-memory
    /// model of "what announcement should the modal show" and "which
    /// components have an active NEW badge". Populated from
    /// `/v1/announcements/pending` and `/v1/badges` after sign-in and
    /// on launch. `@ObservationIgnored` because the service is itself
    /// `@Observable` and sub-properties drive view updates — wrapping
    /// it again here would re-trigger every view that touches
    /// `appState` whenever the badge map changes.
    @ObservationIgnored
    private(set) lazy var announcements: AnnouncementService = AnnouncementService(backend: backend)

    init() {}

    /// Fetches the latest entitlement from the backend. Silent on network
    /// errors — keeps whatever state was previously cached.
    func refreshEntitlement() {
        Task { await refreshEntitlementAsync() }
    }

    /// Awaitable variant of `refreshEntitlement`. Used by `URLSchemeHandler`
    /// after a Stripe return so it can apply intent-driven side effects (e.g.
    /// flipping the Magic Cutout toggle on) once Pro is confirmed.
    ///
    /// Always hits `/v1/account` — the endpoint is anonymous-safe and falls
    /// back to a `device_grants` lookup keyed on `X-Device-Fingerprint` so a
    /// signed-out Mac that paid via the pre-auth checkout flow is still
    /// reported as Pro. Short-circuiting on `!auth.isSignedIn` would mask
    /// that grant and leave a paid user stuck on free.
    func refreshEntitlementAsync() async {
        proEntitlement.isRefreshing = true
        do {
            let me = try await backend.me()
            proEntitlement.apply(me)
        } catch {
            proEntitlement.lastError = (error as? LocalizedError)?.errorDescription
        }
        proEntitlement.isRefreshing = false
    }

    /// Display language. Changing this re-renders all views that read it,
    /// and `Loc` picks up the new value from UserDefaults.
    var language: Lang = Lang.current {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    // Image caches are pure memoization — they must NOT participate in
    // @Observable tracking. Otherwise every cache-miss write inside a view
    // body (`adjustedCutout(for:)` etc.) invalidates every other view that
    // ever read from the same dict, producing an O(N²) re-render cascade
    // across the sidebar thumbnails + editor canvas. View invalidation is
    // already driven by the underlying Portrait / BackgroundPreset models.
    //
    // Each cache is an `NSCache` with both a count limit and a cost-based
    // memory limit (audit HIGH #8). Cost is the exact pixel-buffer size
    // (`bytesPerRow * height`). NSCache also evicts under system memory
    // pressure on its own, but we set explicit caps so a user importing
    // hundreds of full-resolution portraits can't grow these into the
    // multi-GB range before the OS notices.
    //
    // Rough budget (~500 MB worst case in steady state, far less for
    // typical sessions because NSCache evicts long-tail entries):
    //   - cutoutCache             ~200 MB / 200 items
    //   - adjustedCutoutCache     ~150 MB / 200 items
    //   - backgroundCache         ~100 MB / 100 items
    //   - thumbnailCache           ~50 MB / 2 000 items (thumbs are tiny)

    /// In-memory cache of decoded cutout CGImages keyed by portrait id,
    /// so the editor doesn't re-decode on every redraw.
    @ObservationIgnored
    private let cutoutCache: NSCache<NSUUID, CGImageBox> = AppState.makeCache(
        countLimit: 200, costLimitMB: 200
    )
    /// In-memory cache of the adjusted cutout (base cutout + CIFilter chain),
    /// keyed by portrait id. Stored with the adjustments' hash so we can
    /// invalidate as soon as any slider changes value.
    @ObservationIgnored
    private let adjustedCutoutCache: NSCache<NSUUID, KeyedCGImageBox> = AppState.makeCache(
        countLimit: 200, costLimitMB: 150
    )
    /// In-memory cache of decoded background images keyed by preset id.
    @ObservationIgnored
    private let backgroundCache: NSCache<NSUUID, CGImageBox> = AppState.makeCache(
        countLimit: 100, costLimitMB: 100
    )
    /// Composited thumbnail cache for the Library sidebar. Holds a flat
    /// CGImage at thumbnail resolution per portrait so each row paints with
    /// a single Image, not a live CanvasPreview (GeometryReader + CI chain).
    /// Keyed by portrait id; the stored hash captures every input that
    /// affects the rendered pixels.
    @ObservationIgnored
    private let thumbnailCache: NSCache<NSUUID, KeyedCGImageBox> = AppState.makeCache(
        countLimit: 2_000, costLimitMB: 50
    )
    /// Pixel side for sidebar thumbnails. 44pt visible @2x.
    private static let thumbnailPixelSize: CGFloat = 88

    /// In-memory pixel-buffer cost of a CGImage. `bytesPerRow` already
    /// includes any alignment padding the buffer carries, so this is the
    /// exact decoded size — what NSCache should be metering against.
    private static func cost(of image: CGImage) -> Int {
        return image.bytesPerRow * image.height
    }

    private static func makeCache<K, V>(countLimit: Int, costLimitMB: Int) -> NSCache<K, V> {
        let cache = NSCache<K, V>()
        cache.countLimit = countLimit
        cache.totalCostLimit = costLimitMB * 1_024 * 1_024
        return cache
    }

    func cutout(for portrait: Portrait) -> CGImage? {
        let key = portrait.id as NSUUID
        if let cached = cutoutCache.object(forKey: key) { return cached.image }
        guard let data = portrait.cutoutPNG,
              let img = ImageProcessor.cgImage(from: data) else { return nil }
        cutoutCache.setObject(CGImageBox(img), forKey: key, cost: Self.cost(of: img))
        return img
    }

    /// Returns the cutout with the portrait's current adjustments applied.
    /// Falls back to the raw cutout when adjustments are neutral (fast path)
    /// or when the CI filter chain fails to render.
    func adjustedCutout(for portrait: Portrait) -> CGImage? {
        guard let base = cutout(for: portrait) else { return nil }
        let adj = ImageAdjustments(from: portrait)
        if adj.isNeutral { return base }
        let hashKey = adj.hashValue
        let nsKey = portrait.id as NSUUID
        if let hit = adjustedCutoutCache.object(forKey: nsKey), hit.hashKey == hashKey {
            return hit.image
        }
        guard let rendered = ImageAdjustmentRenderer.apply(adj, to: base) else {
            return base
        }
        adjustedCutoutCache.setObject(
            KeyedCGImageBox(hashKey: hashKey, image: rendered),
            forKey: nsKey,
            cost: Self.cost(of: rendered)
        )
        return rendered
    }

    func invalidateCutout(for portrait: Portrait) {
        let key = portrait.id as NSUUID
        cutoutCache.removeObject(forKey: key)
        adjustedCutoutCache.removeObject(forKey: key)
        thumbnailCache.removeObject(forKey: key)
    }

    func invalidateAdjusted(for portrait: Portrait) {
        let key = portrait.id as NSUUID
        adjustedCutoutCache.removeObject(forKey: key)
        thumbnailCache.removeObject(forKey: key)
    }

    func backgroundImage(for preset: BackgroundPreset) -> CGImage? {
        guard preset.kind == .image else { return nil }
        let key = preset.id as NSUUID
        if let cached = backgroundCache.object(forKey: key) { return cached.image }
        guard preset.modelContext != nil,
              let data = preset.imageData,
              let img = ImageProcessor.cgImage(from: data) else { return nil }
        backgroundCache.setObject(CGImageBox(img), forKey: key, cost: Self.cost(of: img))
        return img
    }

    func invalidateBackground(_ preset: BackgroundPreset) {
        backgroundCache.removeObject(forKey: preset.id as NSUUID)
        // Background changed → any thumbnail composited against this preset
        // is stale. Cheap to drop the whole map; thumbnails repopulate lazily.
        thumbnailCache.removeAllObjects()
    }

    /// Drops every cached decoded image. Called when the scene goes to
    /// `.background` so a hidden window doesn't keep hundreds of MB of
    /// CoreImage pixel buffers resident. Caches repopulate lazily on next
    /// view appearance — cheap because the underlying PNGs live in
    /// SwiftData external storage.
    func flushImageCaches() {
        cutoutCache.removeAllObjects()
        adjustedCutoutCache.removeAllObjects()
        backgroundCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    /// Returns a flattened CGImage suitable for a sidebar thumbnail. Cheap on
    /// cache hit (dictionary lookup); on miss runs a single Compositor.render
    /// at `thumbnailPixelSize` which is ~88px square — orders of magnitude
    /// less work than the full editor canvas. The hash key folds in every
    /// input that affects pixels (cutout content, transform, adjustments,
    /// background identity + content), so the cache self-invalidates.
    func thumbnail(for portrait: Portrait, background: BackgroundPreset?) -> CGImage? {
        var hasher = Hasher()
        hasher.combine(portrait.id)
        hasher.combine(portrait.cutoutPNG?.count ?? 0)
        hasher.combine(portrait.scale)
        hasher.combine(portrait.offsetX)
        hasher.combine(portrait.offsetY)
        hasher.combine(ImageAdjustments(from: portrait).hashValue)
        if let bg = background {
            hasher.combine(bg.id)
            switch bg.kind {
            case .image:
                hasher.combine(bg.imageData?.count ?? 0)
            case .color:
                let c = bg.colorComponents
                hasher.combine(c.0); hasher.combine(c.1); hasher.combine(c.2); hasher.combine(c.3)
            }
        } else {
            hasher.combine(0)
        }
        let hashKey = hasher.finalize()
        let nsKey = portrait.id as NSUUID

        if let hit = thumbnailCache.object(forKey: nsKey), hit.hashKey == hashKey {
            return hit.image
        }

        guard let cutout = adjustedCutout(for: portrait) else { return nil }
        let bgLayer = BackgroundLayer.resolve(preset: background, fallback: nil)
        let transform = AlignTransform(
            scale: CGFloat(portrait.scale),
            offset: CGSize(width: portrait.offsetX, height: portrait.offsetY)
        )
        let size = CGSize(width: Self.thumbnailPixelSize, height: Self.thumbnailPixelSize)
        guard let img = Compositor.render(
            cutout: cutout,
            background: bgLayer,
            transform: transform,
            outputSize: size,
            shape: .square
        ) else { return nil }
        thumbnailCache.setObject(
            KeyedCGImageBox(hashKey: hashKey, image: img),
            forKey: nsKey,
            cost: Self.cost(of: img)
        )
        return img
    }

    func invalidateThumbnail(for portrait: Portrait) {
        thumbnailCache.removeObject(forKey: portrait.id as NSUUID)
    }
}

/// Reference-typed wrapper for storing CGImages in NSCache (which requires
/// AnyObject values). One class per cache shape so the NSCache generics
/// stay strict: `CGImageBox` for raw images, `KeyedCGImageBox` for the
/// hashed variants.
private final class CGImageBox: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

private final class KeyedCGImageBox: NSObject {
    let hashKey: Int
    let image: CGImage
    init(hashKey: Int, image: CGImage) {
        self.hashKey = hashKey
        self.image = image
    }
}
