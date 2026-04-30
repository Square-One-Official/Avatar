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

/// Bottom-of-window toast variants. `showsUpgrade` flips the Upgrade pill
/// on/off so we can reuse the same chip for free-tier upsells and Pro-only
/// hard-limit notices.
struct ProToast: Equatable {
    let message: String
    let showsUpgrade: Bool
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
}

@MainActor
@Observable
final class AppState {
    var selectedPortraitID: UUID?
    var isImporting = false
    var isProcessing = false {
        didSet {
            if !isProcessing { processingKind = .cutout }
        }
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
        present(ProToast(message: message, showsUpgrade: true), seconds: seconds)
    }

    /// Pro-user technical limit hit (e.g. batch hard cap): show the same
    /// chip without the Upgrade CTA, since they're already paying.
    func showProInfo(_ message: String, seconds: TimeInterval = 5) {
        present(ProToast(message: message, showsUpgrade: false), seconds: seconds)
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

    init() {}

    /// Fetches the latest entitlement from the backend. Silent on network
    /// errors — keeps whatever state was previously cached.
    func refreshEntitlement() {
        Task { await refreshEntitlementAsync() }
    }

    /// Awaitable variant of `refreshEntitlement`. Used by `URLSchemeHandler`
    /// after a Stripe return so it can apply intent-driven side effects (e.g.
    /// flipping the Magic Cutout toggle on) once Pro is confirmed.
    func refreshEntitlementAsync() async {
        guard auth.isSignedIn else {
            proEntitlement.clear()
            return
        }
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

    /// In-memory cache of decoded cutout CGImages keyed by portrait id,
    /// so the editor doesn't re-decode on every redraw.
    private var cutoutCache: [UUID: CGImage] = [:]
    /// In-memory cache of the adjusted cutout (base cutout + CIFilter chain),
    /// keyed by portrait id. Stored with the adjustments' hash so we can
    /// invalidate as soon as any slider changes value.
    private var adjustedCutoutCache: [UUID: (key: Int, image: CGImage)] = [:]
    /// In-memory cache of decoded background images keyed by preset id.
    private var backgroundCache: [UUID: CGImage] = [:]

    func cutout(for portrait: Portrait) -> CGImage? {
        if let cached = cutoutCache[portrait.id] { return cached }
        guard let data = portrait.cutoutPNG,
              let img = ImageProcessor.cgImage(from: data) else { return nil }
        cutoutCache[portrait.id] = img
        return img
    }

    /// Returns the cutout with the portrait's current adjustments applied.
    /// Falls back to the raw cutout when adjustments are neutral (fast path)
    /// or when the CI filter chain fails to render.
    func adjustedCutout(for portrait: Portrait) -> CGImage? {
        guard let base = cutout(for: portrait) else { return nil }
        let adj = ImageAdjustments(from: portrait)
        if adj.isNeutral { return base }
        let key = adj.hashValue
        if let hit = adjustedCutoutCache[portrait.id], hit.key == key {
            return hit.image
        }
        guard let rendered = ImageAdjustmentRenderer.apply(adj, to: base) else {
            return base
        }
        adjustedCutoutCache[portrait.id] = (key, rendered)
        return rendered
    }

    func invalidateCutout(for portrait: Portrait) {
        cutoutCache.removeValue(forKey: portrait.id)
        adjustedCutoutCache.removeValue(forKey: portrait.id)
    }

    func invalidateAdjusted(for portrait: Portrait) {
        adjustedCutoutCache.removeValue(forKey: portrait.id)
    }

    func backgroundImage(for preset: BackgroundPreset) -> CGImage? {
        guard preset.kind == .image else { return nil }
        if let cached = backgroundCache[preset.id] { return cached }
        guard preset.modelContext != nil,
              let data = preset.imageData,
              let img = ImageProcessor.cgImage(from: data) else { return nil }
        backgroundCache[preset.id] = img
        return img
    }

    func invalidateBackground(_ preset: BackgroundPreset) {
        backgroundCache.removeValue(forKey: preset.id)
    }
}
