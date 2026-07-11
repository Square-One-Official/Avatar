import AppKit
import AvatarKit
import AvatarUI
import SwiftData
import SwiftUI

@main
struct Avatar2App: App {
    @State private var auth: AuthService
    @State private var onboarding: OnboardingModel
    @State private var entitlement: EntitlementModel
    /// E17.5: getargete in-app-berichten (verenigd Message-model).
    @State private var messaging: MessagingService
    /// E13.5 (audit-C1): dé app-brede Sparkle-updater — één SPUUpdater per
    /// proces. Via Environment naar Settings→About; launch doet een
    /// achtergrondcheck (zie `.task` hieronder).
    @State private var updates: UpdateManager

    /// Eigen SwiftData-store voor de set (E05.4). Normaal de persistente store;
    /// onder `--smoke-store` (DEBUG) een GEÏSOLEERDE, gezaaide in-memory store zodat
    /// smoke-screenshots Thierry's echte portretten niet vervuilen.
    private let modelContainer: ModelContainer

    init() {
        // Eén venster, geen tabs: zonder dit injecteert AppKit een eigen
        // "View"-menu (Show Tab Bar / Show All Tabs) náást SwiftUI's View-menu →
        // twee "View"-items in de menubalk. Uitzetten laat alleen ons View-menu
        // (Enter Full Screen + de zoom-acties) over.
        NSWindow.allowsAutomaticWindowTabbing = false

        let auth = AuthService()
        let entitlement = EntitlementModel(auth: auth)
        _auth = State(initialValue: auth)
        _onboarding = State(initialValue: OnboardingModel(auth: auth))
        _entitlement = State(initialValue: entitlement)
        _messaging = State(initialValue: MessagingService(backend: entitlement.backend))
        // E13.5: Sparkle start hier (één per proces); in de unit-test-host
        // valt UpdateManager zelf terug op een no-op-engine.
        _updates = State(initialValue: UpdateManager())
        modelContainer = Self.makeModelContainer()
    }

    /// Bouwt de set-store: persistent in productie, gezaaid in-memory bij
    /// `--smoke-store` (DEBUG-smoke).
    private static func makeModelContainer() -> ModelContainer {
        let models: [any PersistentModel.Type] = [Portrait2.self, Folder2.self, Banner2.self, BannerDoc.self]
        let schema = Schema(models)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--smoke-store") {
            if let container = try? ModelContainer(
                for: schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            ) {
                SmokeSeed.populate(container.mainContext)
                return container
            }
        }
        #endif
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Kon de Avatar2-store niet maken: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarding.isActive {
                    OnboardingFlow(model: onboarding, entitlement: entitlement)
                } else {
                    ShellView(entitlement: entitlement)
                }
            }
            // Punt 18a: minimum waarbij de layout nooit kapot kan (de
            // first-use-ring schaalt mee, 18b); default-opening hieronder.
            .frame(minWidth: 800, minHeight: 600)
            // E49.3: beeld-edits houden volledige PNG-Data in undo-closures;
            // zonder cap groeit de venster-history onbegrensd.
            .undoHistoryCap()
            #if DEBUG
            .task {
                // Smoke-run-haak (--onboarding-step <stap>): forceer de flow
                // open op een stap voor de visuele verificatie.
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "--onboarding-step"),
                   args.indices.contains(i + 1) {
                    switch args[i + 1] {
                    case "privacy": onboarding.debugForce(step: .privacy)
                    case "download": onboarding.debugForce(step: .download)
                    case "email": onboarding.debugForce(step: .email)
                    case "otp": onboarding.debugForce(step: .otp)
                    case "splash": onboarding.debugForce(step: .splash)
                    default: break
                    }
                }
                // E14.1: `--show-paywall` opent de plan-kiezer voor de smoke.
                if args.contains("--show-paywall") { entitlement.requestUpgrade() }
                // E14.5: top-up-variant van de paywall (Pro op=op).
                if args.contains("--show-paywall-topup") {
                    entitlement.debugForceTopup = true
                    entitlement.requestUpgrade()
                }
                // E15.5: --dev-advanced wordt in EntitlementModel.init gelezen
                // (vóór first render), niet hier — zie de toelichting daar.
                // E17.5: forceer een test-bericht voor de smoke.
                if args.contains("--show-message") {
                    messaging.debugInject(Message(
                        slug: "smoke-welcome",
                        title: "Welcome to Aaavatar 2",
                        body: "**New:** styles, hair and clothing edits — all in one place.",
                        cta: .init(label: "Explore effects", url: URL(string: "aaavatar://effects")!)
                    ))
                }
            }
            #endif
            // E17.5: getargete berichten ophalen bij app-start (faalt stil).
            .task { await messaging.refresh() }
            // E13.5 (audit-C1): achtergrond-update-check bij launch — About
            // hoeft nooit open. Eenmalig per proces (guard in de manager) en
            // respecteert de "Automatic updates"-toggle.
            .task { updates.checkForUpdatesInBackgroundAtLaunch() }
            // E13.5: dezelfde instance voor Settings→About (geen tweede
            // SPUUpdater per proces).
            .environment(updates)
            // Account-fix: de Supabase-sessie (bearer-token) wordt ASYNC hersteld
            // via authStateChanges ná launch. De vroege refresh (ShellTopBar) haalt
            // dan nog het ANONIEME account op (geen Pro, 0 credits) → alle pro-
            // features vielen in de paywall. Her-fetch het account zodra het token
            // er is (isSignedIn flipt) zodat Pro/credits kloppen.
            .onChange(of: entitlement.isSignedIn) { _, signedIn in
                if signedIn {
                    Task { await entitlement.refresh() }
                } else {
                    // E04.8: sign-out → als de onboarding weer actief wordt
                    // (hasCompleted == false), begint die op splash i.p.v.
                    // een verweesde tussenstap.
                    onboarding.resetToSplash()
                }
            }
            // E17.5: in-app bericht-sheet (overlay → geen layoutshift).
            .overlay { messageOverlay }
            .animation(.easeOut(duration: 0.18), value: messaging.current)
            // E01.14: géén handmatige setFrameAutosaveName meer — SwiftUI's
            // WindowGroup persisteert het venster-frame zelf (defaultSize bij
            // eerste start, daarna de gebruikersmaat). Twee autosave-bronnen
            // op één NSWindow lieten het hiddenTitleBar-venster inklappen.
            .sheet(isPresented: Binding(
                get: { entitlement.isPaywallPresented },
                set: { entitlement.isPaywallPresented = $0 }
            )) {
                PaywallSheet(model: entitlement)
            }
            // E18.23: toasts rechtsONDERin, met slide-in/out — niet meer
            // centraal-onder waar ze knoppen overlapten.
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if entitlement.isShowingOutOfCreditsToast {
                        OutOfCreditsToastView(model: entitlement)
                    } else if let ctx = entitlement.workingContext {
                        WorkingToastView(context: ctx) {
                            entitlement.dismissWorkingToast()
                        }
                    } else if let message = entitlement.errorToast {
                        // E18.3: cloud-fout als toast i.p.v. inline tekst.
                        // E44.1: duur uit het model (≥ 8s) — 4s was zo kort
                        // dat een echte fout onopgemerkt bleef.
                        DSToast(title: "Something went wrong", description: message) {
                            entitlement.dismissErrorToast()
                        }
                        .task {
                            try? await Task.sleep(for: EntitlementModel.errorToastDuration)
                            entitlement.dismissErrorToast()
                        }
                    }
                }
                .padding(DSSpacing.gap5)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            .animation(.spring(duration: 0.3), value: entitlement.errorToast)
            .animation(.spring(duration: 0.3), value: entitlement.workingContext != nil)
            .animation(.spring(duration: 0.3), value: entitlement.isShowingOutOfCreditsToast)
            // Privacy Tier Picker: elevation modal → Settings.
            .overlay {
                if let request = entitlement.privacyElevation {
                    ZStack {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .onTapGesture { entitlement.dismissPrivacyElevation() }
                        PrivacyElevationSheet(
                            request: request,
                            onOpenSettings: { entitlement.openPrivacySettings() },
                            onDismiss: { entitlement.dismissPrivacyElevation() }
                        )
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: entitlement.privacyElevation)
            // E18.2: gate — inloggen om Pro te checken.
            .sheet(isPresented: Binding(
                get: { entitlement.cloudGate == .signIn },
                set: { if !$0 { entitlement.dismissCloudGate() } }
            )) {
                SignInSheet(entitlement: entitlement)
            }
            // E15.1: persistente Theme-voorkeur (Preferences > Appearance).
            .appliedAppearancePreference()
        }
        // Zoom-bediening leeft in de menubalk (View-menu) i.p.v. een zwevende
        // HUD op de canvas. De items werken op de focused scene value die de
        // actieve EditorView publiceert; geen canvas → uitgegrijsd.
        // We hángen aan het systeem-View-menu (`.sidebar`-plaatsing) i.p.v. een
        // eigen `CommandMenu("View")` — dat laatste maakte een TWEEDE menu met
        // dezelfde titel naast het AppKit-View-menu (Enter Full Screen/tabs).
        .commands {
            // ⌘, → in-venster Settings (vervangt het standaard uitgegrijsde item).
            CommandGroup(replacing: .appSettings) {
                SettingsCommands()
            }
            CommandGroup(after: .sidebar) {
                Divider()
                CanvasZoomCommands()
            }
            // E49.2: ⌘U app-breed in het File-menu (werkt ook op board/editor);
            // zelfde focused-scene-value-patroon als SettingsCommands hierboven.
            CommandGroup(after: .newItem) {
                UploadPortraitCommands()
            }
        }
        // Eigen SwiftData-store voor de set (E05.4) — los van de v1-store.
        // PoC (left-nav): Folder2 voor de Portraits-galerij, E35.1: Banner2 voor de
        // Banners-bibliotheek. De container wordt in `init` gebouwd (persistent, of
        // gezaaid in-memory bij `--smoke-store`).
        .modelContainer(modelContainer)
        // Bevinding 1 (E04.5): Figma kent geen aparte titelbalk — één zwart
        // vlak, traffic lights inline, geen venstertitel. hiddenTitleBar
        // geeft full-size content; de topbar reserveert zelf ruimte naast
        // de window-controls.
        .windowStyle(.hiddenTitleBar)
        // E15.1 + punt 14: Settings leeft BINNEN het hoofdvenster (view-
        // state in ShellView, gear toggelt) — geen aparte Settings-scene;
        // de frames vullen het hele app-venster.
        // Punt 18a: opent ruim boven de 1000×700-ontwerpmaat van de frames.
        .defaultSize(width: 1100, height: 760)
        // E01.14: laat het venster nooit kleiner worden dan een werkbare
        // maat — extra vangnet naast de content-minHeight, zodat een ambigue
        // contenthoogte het venster niet kan laten inklappen.
        .windowResizability(.contentMinSize)
    }

    /// E17.5: gecentreerd in-app bericht-sheet boven een gedimde backdrop.
    /// Overlay, dus geen layoutshift; backdrop-tik of het kruis sluit.
    @ViewBuilder
    private var messageOverlay: some View {
        if let message = messaging.current {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { messaging.dismiss(message) }
                DSMessageSheet(
                    title: message.title,
                    body: message.body,
                    imageURL: message.imageUrl,
                    ctaLabel: message.cta?.label,
                    onCTA: {
                        // E17.5: alleen web-/eigen schema's openen — een CMS-bericht
                        // mag geen willekeurig URL-schema (file://, andere apps) starten.
                        if let url = message.cta?.url, url.isAllowedExternalScheme {
                            NSWorkspace.shared.open(url)
                        }
                        messaging.acknowledge(message)
                    },
                    onDismiss: { messaging.dismiss(message) }
                )
                .padding(DSSpacing.gap8)
            }
            .transition(.opacity)
        }
    }
}

