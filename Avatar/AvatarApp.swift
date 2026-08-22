import SwiftUI
import SwiftData
import AppKit

// MARK: - Theme

// Darker dark-mode palette (Linear/Claude-Desktop inspired). Light mode is
// untouched — these resolve to the system colors when not in dark mode.
extension Color {
    /// Main canvas / window background. Deeper than `windowBackgroundColor`
    /// in dark mode for a Linear-like near-black canvas.
    static let appCanvas = Color(nsColor: .appCanvas)

    /// Slightly elevated surface for cards, search bars, preset tiles.
    static let appSurface = Color(nsColor: .appSurface)

    /// Brand periwinkle blue. Primary action color — CTAs, links, drop-zone
    /// accents, Pro upsell surfaces. Same value in light and dark mode.
    static let appBrand = Color(red: 0x5E / 255.0, green: 0x99 / 255.0, blue: 1.0)

    // MARK: Status palette
    //
    // Four severity levels, each with a soft fill + matching ink (text / icon
    // foreground). Use via `StatusChip` so every surface inherits the same
    // padding, radius, weight and animation. Don't pick `.red`/`.yellow`
    // directly in views — the system color reds are too aggressive against
    // the dark canvas, and the muted Ink variants below stay legible against
    // their soft fill backgrounds.
    //
    //   info     blue periwinkle   tips, neutral upsells, links
    //   success  green             "done", "saved", positive feedback
    //   warning  amber             recoverable: offline, retrying, soft caps
    //   danger   muted red         destructive or unrecoverable failures

    static let appInfo       = Color(nsColor: .appInfo)
    static let appInfoInk    = Color(nsColor: .appInfoInk)
    static let appSuccess    = Color(nsColor: .appSuccess)
    static let appSuccessInk = Color(nsColor: .appSuccessInk)
    static let appWarning    = Color(nsColor: .appWarning)
    static let appWarningInk = Color(nsColor: .appWarningInk)
    static let appDanger     = Color(nsColor: .appDanger)
    static let appDangerInk  = Color(nsColor: .appDangerInk)
}

extension NSColor {
    static let appCanvas = NSColor(name: NSColor.Name("appCanvas")) { appearance in
        if appearance.isDarkMode {
            return NSColor(srgbRed: 0x0B/255, green: 0x0B/255, blue: 0x0D/255, alpha: 1)
        }
        return .windowBackgroundColor
    }

    static let appSurface = NSColor(name: NSColor.Name("appSurface")) { appearance in
        if appearance.isDarkMode {
            return NSColor(srgbRed: 0x16/255, green: 0x16/255, blue: 0x18/255, alpha: 1)
        }
        return .controlBackgroundColor
    }

    // MARK: - Status palette implementations
    //
    // Hex picks per appearance: the dark-mode fill carries some alpha so it
    // reads as a tinted overlay rather than a solid pop, the light-mode fill
    // is flatter because the canvas is already bright. Ink colors target
    // ~7:1 contrast on the fill for AA Large Text legibility.

    static let appInfo = NSColor(name: NSColor.Name("appInfo")) { appearance in
        if appearance.isDarkMode {
            return NSColor(srgbRed: 0x6E/255, green: 0x90/255, blue: 0xE8/255, alpha: 0.90)
        }
        return NSColor(srgbRed: 0xC4/255, green: 0xD3/255, blue: 0xFF/255, alpha: 1)
    }
    static let appInfoInk = NSColor(name: NSColor.Name("appInfoInk")) { appearance in
        if appearance.isDarkMode {
            return NSColor(srgbRed: 0xE6/255, green: 0xEE/255, blue: 0xFF/255, alpha: 1)
        }
        return NSColor(srgbRed: 0x1B/255, green: 0x2E/255, blue: 0x6E/255, alpha: 1)
    }

    static let appSuccess = NSColor(name: NSColor.Name("appSuccess")) { appearance in
        if appearance.isDarkMode {
            return NSColor(srgbRed: 0x34/255, green: 0x9A/255, blue: 0x5A/255, alpha: 0.90)
        }
        return NSColor(srgbRed: 0xBF/255, green: 0xEA/255, blue: 0xCB/255, alpha: 1)
    }
    static let appSuccessInk = NSColor(name: NSColor.Name("appSuccessInk")) { appearance in
        if appearance.isDarkMode {
            return NSColor(srgbRed: 0xD8/255, green: 0xF2/255, blue: 0xDF/255, alpha: 1)
        }
        return NSColor(srgbRed: 0x10/255, green: 0x4A/255, blue: 0x29/255, alpha: 1)
    }

    static let appWarning = NSColor(name: NSColor.Name("appWarning")) { appearance in
        if appearance.isDarkMode {
            // Warm amber, slightly muted so it doesn't scream against the
            // near-black canvas. Carries enough yellow to read as warning
            // rather than failure.
            return NSColor(srgbRed: 0xC8/255, green: 0x8A/255, blue: 0x1E/255, alpha: 0.92)
        }
        return NSColor(srgbRed: 0xF4/255, green: 0xB7/255, blue: 0x3E/255, alpha: 0.95)
    }
    static let appWarningInk = NSColor(name: NSColor.Name("appWarningInk")) { appearance in
        if appearance.isDarkMode {
            return NSColor(srgbRed: 0xFF/255, green: 0xE6/255, blue: 0xB8/255, alpha: 1)
        }
        return NSColor(srgbRed: 0x6B/255, green: 0x44/255, blue: 0x05/255, alpha: 1)
    }

    static let appDanger = NSColor(name: NSColor.Name("appDanger")) { appearance in
        if appearance.isDarkMode {
            // Muted brick — distinct from system red so destructive surfaces
            // still feel deliberate but not panicky.
            return NSColor(srgbRed: 0xB1/255, green: 0x42/255, blue: 0x3A/255, alpha: 0.92)
        }
        return NSColor(srgbRed: 0xF2/255, green: 0xC0/255, blue: 0xBC/255, alpha: 1)
    }
    static let appDangerInk = NSColor(name: NSColor.Name("appDangerInk")) { appearance in
        if appearance.isDarkMode {
            return NSColor(srgbRed: 0xFD/255, green: 0xDF/255, blue: 0xDB/255, alpha: 1)
        }
        return NSColor(srgbRed: 0x70/255, green: 0x1B/255, blue: 0x14/255, alpha: 1)
    }
}

extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .vibrantDark,
                         .accessibilityHighContrastDarkAqua,
                         .accessibilityHighContrastVibrantDark]) != nil
    }
}

// MARK: - Window background painter

/// Repaints the host `NSWindow.backgroundColor` so the title bar and detail
/// area match `appCanvas` instead of macOS's default dark gray. Without this
/// the chrome stays a couple of shades lighter than the rest of the UI.
///
/// `colorScheme` is read so SwiftUI re-invokes `updateNSView` when the user
/// toggles appearance — `NSWindow.backgroundColor` caches the resolved color
/// and won't re-evaluate the dynamic `appCanvas` on its own. KVO on
/// `effectiveAppearance` covers the "Match System" case where the system
/// switches without any SwiftUI state change.
struct WindowBackgroundPainter: NSViewRepresentable {
    let colorScheme: ColorScheme?

    final class Coordinator: NSObject {
        var observation: NSKeyValueObservation?
        var latestColorScheme: ColorScheme?
        /// Last `colorScheme` actually pushed through `paint()`. Used to skip
        /// no-op repaints — `updateNSView` fires on every parent body
        /// re-evaluation, but `paint()` walks the entire NSView tree marking
        /// `needsDisplay = true`, which forces AppKit to redraw materials and
        /// other bridged views, which invalidates SwiftUI views, which
        /// re-evaluates the parent and calls `updateNSView` again. The result
        /// was a display-rate feedback loop that pinned CPU at ~90% on idle.
        var hasAppliedScheme: Bool = false
        var lastAppliedScheme: ColorScheme?
        deinit { observation?.invalidate() }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.latestColorScheme = colorScheme
        context.coordinator.hasAppliedScheme = true
        context.coordinator.lastAppliedScheme = colorScheme
        DispatchQueue.main.async { [coordinator = context.coordinator] in
            paint(view, colorScheme: coordinator.latestColorScheme)
            if let window = view.window, coordinator.observation == nil {
                // System-driven flips while in "Match System" mode don't
                // trigger updateNSView — observe the window directly so the
                // background follows along. Use the coordinator's latest
                // value so a self-triggered KVO firing (we just set
                // `window.appearance`) repaints with the same scheme rather
                // than clobbering it back to "follow system".
                coordinator.observation = window.observe(
                    \.effectiveAppearance,
                    options: [.new]
                ) { [weak view, weak coordinator] _, _ in
                    guard let view, let coordinator else { return }
                    // Only repaint when the resolved scheme actually changed.
                    // Without this guard, any external bump to
                    // `effectiveAppearance` (NSVisualEffectView re-resolving,
                    // an NSAppearance push from a popover, etc.) re-runs
                    // `paint()`, which recursively dirties every NSView via
                    // `invalidateAppearance` — feeding the next display cycle
                    // a full repaint that pegs CPU even when nothing changed.
                    let next = coordinator.latestColorScheme
                    if coordinator.hasAppliedScheme,
                       coordinator.lastAppliedScheme == next {
                        return
                    }
                    coordinator.hasAppliedScheme = true
                    coordinator.lastAppliedScheme = next
                    DispatchQueue.main.async {
                        paint(view, colorScheme: next)
                    }
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.latestColorScheme = colorScheme
        if context.coordinator.hasAppliedScheme,
           context.coordinator.lastAppliedScheme == colorScheme {
            return
        }
        context.coordinator.hasAppliedScheme = true
        context.coordinator.lastAppliedScheme = colorScheme
        let scheme = colorScheme
        DispatchQueue.main.async { paint(nsView, colorScheme: scheme) }
    }
}

private func paint(_ view: NSView, colorScheme: ColorScheme?) {
    guard let window = view.window else { return }
    // SwiftUI's `.preferredColorScheme()` doesn't reliably propagate to
    // `NSWindow.appearance`, so the title bar / chrome stays on the old
    // appearance even when the SwiftUI content flips. Set it ourselves so
    // the title bar follows, and so the dynamic `appCanvas` color resolves
    // against the right appearance when we re-assign `backgroundColor`.
    let target: NSAppearance? = switch colorScheme {
    case .light: NSAppearance(named: .aqua)
    case .dark:  NSAppearance(named: .darkAqua)
    case nil:    nil           // Match System
    case .some:  nil
    }
    window.appearance = target
    window.backgroundColor = .appCanvas
    window.titlebarAppearsTransparent = true
    if window.frameAutosaveName.isEmpty {
        window.setFrameAutosaveName("MainWindow")
    }
    // The NSTableView backing SwiftUI's sidebar List caches its drawing and
    // doesn't always pick up a new effectiveAppearance — its selection pill
    // ends up rendered against the previous palette. Walk the content tree
    // and mark everything dirty so the next draw uses the new appearance.
    if let content = window.contentView { invalidateAppearance(content) }
}

private func invalidateAppearance(_ view: NSView) {
    view.needsDisplay = true
    for sub in view.subviews { invalidateAppearance(sub) }
}

/// Recovery path for a corrupt SwiftData store. Offers the user a one-click
/// reset (deletes default.store + .shm + .wal sidecars) before falling back
/// to an in-memory store so the app can still launch.
private func recoverModelContainer(
    schema: Schema,
    config: ModelConfiguration,
    initialError: Error
) -> ModelContainer {
    let alert = NSAlert()
    alert.messageText = "Aaavatar's library couldn't be opened"
    alert.informativeText = """
    The on-disk database is unreadable. Resetting clears your imported portraits but lets the app launch.

    Details: \(initialError.localizedDescription)
    """
    alert.alertStyle = .critical
    alert.addButton(withTitle: "Reset and Continue")
    alert.addButton(withTitle: "Quit")

    if alert.runModal() == .alertFirstButtonReturn {
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? FileManager.default.removeItem(at: appSupport.appendingPathComponent(name))
        }
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }
    } else {
        exit(1)
    }

    // Last-resort: in-memory store so the user isn't stranded. Imported
    // portraits won't persist across launches until the disk store recovers.
    let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    if let container = try? ModelContainer(for: schema, configurations: [memoryConfig]) {
        return container
    }
    fatalError("Could not create ModelContainer (disk + memory both failed): \(initialError)")
}

/// Tracks the system's effective appearance so "Match System" can resolve
/// to a concrete `ColorScheme`. SwiftUI's `.preferredColorScheme(nil)` does
/// not clear a previously-applied override (Light → Match System leaves
/// some views stuck in light), so we always pass a concrete value.
@MainActor
@Observable
final class SystemAppearanceObserver {
    private(set) var isDark: Bool = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        // NSApp may not be ready when @State defaults are first evaluated, so
        // poll once on the next runloop tick to capture the real appearance,
        // then start KVO observation. Also listen for the macOS-wide
        // AppleInterfaceThemeChangedNotification as a belt-and-braces signal,
        // since `NSApp.effectiveAppearance` KVO occasionally misses fires
        // when the user has set an explicit per-window appearance elsewhere.
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
            self?.startObserving()
        }
        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    private func refresh() {
        // We never set `NSApp.appearance`, so `effectiveAppearance` reflects
        // the system setting. Per-window overrides (set by our painter) do
        // not affect the application-level appearance.
        isDark = NSApp?.effectiveAppearance.isDarkMode ?? false
    }

    private func startObserving() {
        observation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
}

@main
struct AvatarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var systemAppearance = SystemAppearanceObserver()
    #if !APP_STORE
    @State private var updater = UpdateManager()
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearanceMode") private var appearanceRaw: String = AppearanceMode.dark.rawValue
    private var colorScheme: ColorScheme {
        let mode = AppearanceMode(rawValue: appearanceRaw) ?? .dark
        switch mode {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return systemAppearance.isDark ? .dark : .light
        }
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Portrait.self,
            BackgroundPreset.self,
            ExportPreset.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            return recoverModelContainer(schema: schema, config: config, initialError: error)
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(appState)
                #if !APP_STORE
                .environment(updater)
                #endif
                .environment(appState.magicCutoutPrefs)
                // Make the announcement service reachable from any view —
                // the `.newBadge(...)` modifier reads it via the
                // environment so feature affordances anywhere in the
                // window can opt into the NEW pill without prop-drilling.
                .environment(appState.announcements)
                .environment(appState.privacyPrefs)
                .environment(appState.modelManager)
                // Minimum ensures the library sidebar (~200), canvas (~280)
                // and inspector (~320) all have enough room to display
                // their content without truncation.
                .frame(minWidth: 860, minHeight: 520)
                .background(WindowBackgroundPainter(colorScheme: colorScheme).frame(width: 0, height: 0))
                .preferredColorScheme(colorScheme)
                .id(appState.language)
                .handlesExternalEvents(preferring: ["aaavatar"], allowing: ["aaavatar"])
                .onAppear {
                    appDelegate.configure(appState: appState, container: sharedModelContainer)
                }
                .task {
                    SeedData.seedIfNeeded(context: sharedModelContainer.mainContext)
                    #if !APP_STORE
                    updater.checkForUpdatesInBackground()
                    #endif
                }
                // Flush decoded image caches when the window is fully
                // hidden (audit HIGH #8). NSCache also evicts under system
                // memory pressure on its own, but a backgrounded window
                // sitting idle for hours shouldn't keep hundreds of MB of
                // CoreImage buffers resident "just in case". Repopulation
                // on next foreground is cheap — the source PNGs live in
                // SwiftData external storage.
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        appState.flushImageCaches()
                        // Audit MEDIUM #28: cancel any in-flight import
                        // pipelines so a backgrounded window doesn't keep
                        // burning CPU + holding refs to large UIImages
                        // for an import the user is no longer watching.
                        appState.cancelInFlightImports()
                    }
                }
        }
        .defaultSize(width: 1100, height: 720)
        .defaultPosition(.center)
        .modelContainer(sharedModelContainer)
        .commands {
            AvatarCommands()
            #if DEBUG
            // Subject-Lift V1/V2 benchmark harness. Reads fixtures from
            // Avatar/Debug/Fixtures/ (or $AVATAR_BENCH_FIXTURES) and writes
            // side-by-side cutouts to ~/Desktop/edge-bench-<stamp>/ for
            // perceptual A/B. Compiled out of Release builds.
            CommandMenu("Debug") {
                // Full pass — every fixture, ~1-3 min on M1 with ~25 photos.
                // Use after V2 tweaks to confirm a candidate generalises.
                Button("Run Subject-Lift Benchmark (Full)") {
                    EdgeBenchmark.run()
                }
                // Quick pass — 5 random fixtures, ~10-30s. Use while iterating
                // on a single V2 parameter so the eyeball loop stays tight.
                Button("Run Subject-Lift Benchmark (Quick — 5 Random)") {
                    EdgeBenchmark.run(sampleSize: 5)
                }
                Button("Open Latest Benchmark Folder") {
                    EdgeBenchmark.revealLatest()
                }
                // The app is sandboxed, so reading photos from outside the
                // container needs a security-scoped bookmark. The first
                // benchmark run prompts automatically; this lets the dev
                // re-pick the folder if they move the worktree.
                Button("Choose Fixtures Folder…") {
                    EdgeBenchmark.chooseFixturesFolder()
                }
                Divider()
                // V2 is now default-on. Toggle reflects the actual default
                // (true) when the key is unset; flipping off is the explicit
                // V1 opt-out for debugging real-world regressions.
                Toggle("Use Subject-Lift V2",
                       isOn: Binding(
                        get: { (UserDefaults.standard.object(forKey: "subjectLiftV2") as? Bool) ?? true },
                        set: { UserDefaults.standard.set($0, forKey: "subjectLiftV2") }
                       ))
                Divider()
                // Wipe just the onboarding-related defaults so the next
                // launch hits the first-launch path. Library, portraits,
                // auth session, Magic Cutout toggle, and V2 preference
                // stay intact — this is for *flow* testing, not "reset
                // the whole app". Asks the user to quit so the running
                // process's UserDefaults cache doesn't reinstate the
                // values via the migration shim before we observe the
                // change.
                Button("Reset Onboarding…") {
                    let keys = [
                        "hasSeenOnboarding",
                        "hasSeenWelcomeSignIn",
                        "hasRunOnboardingMigration",
                        "aiPrivacyMode",
                        "localCutoutEngine",
                    ]
                    for key in keys {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                    let alert = NSAlert()
                    alert.messageText = "Onboarding state cleared"
                    alert.informativeText = "Quit Aaavatar (⌘Q) and relaunch to see the first-launch flow. Library, auth, and other preferences are unchanged."
                    alert.alertStyle = .informational
                    alert.runModal()
                }
            }
            #endif
        }
        .handlesExternalEvents(matching: ["aaavatar"])

        Settings {
            SettingsView()
                .environment(appState)
                #if !APP_STORE
                .environment(updater)
                #endif
                .environment(appState.magicCutoutPrefs)
                .environment(appState.announcements)
                .environment(appState.privacyPrefs)
                .environment(appState.modelManager)
                .modelContainer(sharedModelContainer)
                .preferredColorScheme(colorScheme)
                .id(appState.language)
        }
    }
}
