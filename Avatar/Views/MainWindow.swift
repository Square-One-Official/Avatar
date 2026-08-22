import SwiftUI
import SwiftData
import CoreSpotlight

struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \Portrait.updatedAt, order: .reverse) private var portraits: [Portrait]
    @Query private var backgrounds: [BackgroundPreset]

    /// Legacy flag from the single-step welcome sheet. Read here only for
    /// the one-shot migration: existing users who already saw the old
    /// flow are mapped to `hasSeenOnboarding = true + cloudAllowed +
    /// appleVision` so behaviour is preserved and the new sheet never
    /// appears for them.
    @AppStorage("hasSeenWelcomeSignIn") private var hasSeenWelcomeSignIn = false
    /// New first-launch flag for the three-step onboarding. The sheet
    /// flips this on completion (Done) or by skipping the auth step + a
    /// privacy choice. Sticky across launches.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    /// One-shot guard for the file-storage migration (build 6+). Without
    /// this, every signed-out launch would re-show the welcome sheet for
    /// users who chose to stay signed-out. Sticky across launches.
    @AppStorage("hasRunFileAuthMigration") private var hasRunFileAuthMigration = false
    /// One-shot migration: legacy `hasSeenWelcomeSignIn` users get auto-
    /// promoted to `hasSeenOnboarding = true` with the today-equivalent
    /// privacy posture. Runs at most once per install regardless of
    /// subsequent state changes.
    @AppStorage("hasRunOnboardingMigration") private var hasRunOnboardingMigration = false
    /// Drives the `.sheet(isPresented:)` binding for the onboarding flow.
    /// Decoupled from `hasSeenOnboarding` so flipping the AppStorage at
    /// the end of the flow doesn't fight the sheet's own dismiss
    /// transition.
    @State private var showOnboardingSheet = false
    @State private var librarySearch = ""
    @State private var isSearchPresented = false

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            LibraryView(search: librarySearch)
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
        } detail: {
            ZStack(alignment: .bottom) {
                if state.selectedPortraitIDs.count > 1 {
                    MultiSelectionView(
                        portraits: portraits.filter { state.selectedPortraitIDs.contains($0.id) }
                    )
                } else if let id = state.selectedPortraitID,
                          let portrait = portraits.first(where: { $0.id == id }) {
                    EditorView(portrait: portrait)
                } else {
                    ImportDropZone()
                }

                if let toast = state.proUpsellToast {
                    ProUpsellToastView(toast: toast,
                                       onUpgrade: { appState.showProUpgradeSheet = true },
                                       onDismiss: { appState.dismissProUpsell() })
                        .padding(.bottom, 28)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .zIndex(2)
                }
            }
            .motionAwareAnimation(.easeOut(duration: 0.22), value: state.proUpsellToast)
        }
        .searchable(
            text: $librarySearch,
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: Text(Loc.searchPlaceholder)
        )
        .onChange(of: appState.librarySearchFocusToken) { _, _ in
            isSearchPresented = true
        }
        .toolbar(id: "mainWindow") {
            ToolbarItem(id: "import", placement: .primaryAction) {
                if state.selectedPortraitID != nil {
                    Button {
                        PortraitLibrary.importFromOpenPanel(context: context, appState: appState)
                    } label: {
                        Label(Loc.importPhoto, systemImage: "plus")
                    }
                    .help(Loc.importPhotoHelp)
                }
            }
            ToolbarItem(id: "exportSelection", placement: .primaryAction) {
                if state.selectedPortraitIDs.count > 1 {
                    Button {
                        state.libraryExportPortraitIDs = state.selectedPortraitIDs
                    } label: {
                        Label(Loc.export, systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("\(Loc.export) \(state.selectedPortraitIDs.count) \(Loc.portraitsPlural)")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { !state.libraryExportPortraitIDs.isEmpty },
            set: { if !$0 { state.libraryExportPortraitIDs = [] } }
        )) {
            ExportSheet(
                portraits: portraits.filter { state.libraryExportPortraitIDs.contains($0.id) },
                backgroundResolver: { background(for: $0) }
            )
        }
        .sheet(isPresented: $state.showProUpgradeSheet) {
            ProUpgradeSheet()
                .environment(appState)
        }
        .sheet(isPresented: $showOnboardingSheet) {
            OnboardingSheet()
                .environment(appState)
                .environment(appState.privacyPrefs)
                // Engine step's inline download progress reads
                // `manager.state`, so the sheet has to carry the same
                // ModelManager instance the rest of the app sees.
                // Without this, the env lookup fails at runtime and
                // SwiftUI silently shows a blank space where the
                // progress bar should go.
                .environment(appState.modelManager)
        }
        .sheet(item: Binding(
            get: { appState.announcements.current },
            set: { newValue in
                // Externally-cleared (announcement service set current to
                // nil) → no-op. Sheet's own dismiss-side cleanup is owned
                // by AnnouncementService.dismiss().
                if newValue == nil { appState.announcements.current = nil }
            }
        )) { announcement in
            AnnouncementSheet(announcement: announcement)
                .environment(appState.announcements)
        }
        .alert(
            Loc.magicCutoutTitle,
            isPresented: Binding(
                get: { state.batchConfirm != nil },
                set: { if !$0 { state.batchConfirm?.onCancel() } }
            ),
            presenting: state.batchConfirm
        ) { request in
            Button(Loc.cancel, role: .cancel) { request.onCancel() }
            Button(Loc.magicCutoutUseCredits(request.credits)) { request.onConfirm() }
        } message: { request in
            Text(Loc.magicCutoutBatchConfirm(request.count, credits: request.credits))
        }
        .onOpenURL { url in
            URLSchemeHandler.handle(url, appState: appState)
        }
        .focusedSceneValue(\.appState, appState)
        .onReceive(NotificationCenter.default.publisher(for: .aaavatarRequestImport)) { _ in
            PortraitLibrary.importFromOpenPanel(context: context, appState: appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aaavatarSelectPortrait)) { note in
            guard let id = note.object as? UUID else { return }
            appState.selectedPortraitIDs = [id]
        }
        .onChange(of: appState.importRequestToken) { _, _ in
            PortraitLibrary.importFromOpenPanel(context: context, appState: appState)
        }
        .onChange(of: appState.deleteRequestToken) { _, _ in
            deleteSelection()
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let idString = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let id = UUID(uuidString: idString) else { return }
            appState.selectedPortraitIDs = [id]
        }
        .task {
            // Refresh Pro entitlement on launch so the badge/credits are accurate.
            // Supabase restores the file-backed session asynchronously, so this
            // first call typically fires before `auth.isSignedIn` flips true —
            // the `onChange` below catches that transition and re-fires.
            appState.refreshEntitlement()
            PortraitSpotlight.reindexAll(portraits: portraits)

            // Storage migration (build 6+): a returning user whose previous
            // session lived in the Keychain has nothing in the new file
            // storage. Re-arm the legacy welcome flag so the migration
            // step below routes them through the new onboarding. Runs at
            // most once, regardless of subsequent sign-out behaviour.
            if !hasRunFileAuthMigration {
                hasRunFileAuthMigration = true
                if hasSeenWelcomeSignIn && !FileAuthStorage().hasAnySession() {
                    hasSeenWelcomeSignIn = false
                }
            }

            // Onboarding migration (this build): map any user who already
            // saw the legacy single-step welcome sheet to the new flag
            // with `cloudAllowed + appleVision` defaults. That preserves
            // exactly today's behaviour (Magic Cutout still works, photos
            // still upload, etc.) without re-onboarding them. The
            // `PrivacyPreferences` defaults registration already provides
            // those values, so we only need to flip `hasSeenOnboarding`.
            if !hasRunOnboardingMigration {
                hasRunOnboardingMigration = true
                if hasSeenWelcomeSignIn {
                    hasSeenOnboarding = true
                }
            }

            // First-launch onboarding. Present when the user hasn't
            // completed it AND isn't already signed in (a returning user
            // whose session restored shouldn't be asked to sign in again,
            // but we still want to capture the privacy posture — for
            // those, jump them straight to the privacy step instead).
            if !hasSeenOnboarding {
                showOnboardingSheet = true
            }

            // Announcements + NEW badges. Badges fetch anonymously so a
            // signed-out user still sees the pill; the pending-pop-up
            // path only runs once we have a session, since the seen-
            // state filter requires a user id. Skip the modal in
            // local-only — CMS campaigns mostly pitch cloud features.
            await appState.announcements.refreshBadges()
            if appState.auth.isSignedIn,
               appState.privacyPrefs.cloudAllowed {
                await appState.announcements.fetchPending()
            }
        }
        .onChange(of: appState.auth.isSignedIn) { _, signedIn in
            if signedIn {
                appState.refreshEntitlement()
                Task {
                    // Brief stagger lets the WelcomeSignInSheet finish its
                    // dismiss animation before the announcement sheet
                    // tries to present — macOS won't show two sheets at
                    // once and would silently swallow the second.
                    try? await Task.sleep(for: .milliseconds(450))
                    await appState.announcements.refreshBadges()
                    if appState.privacyPrefs.cloudAllowed {
                        await appState.announcements.fetchPending()
                    }
                }
            }
        }
        .onChange(of: appState.privacyPrefs.mode) { _, mode in
            if mode == .localOnly {
                // Drop an in-flight cloud pitch without marking it seen,
                // so allowing cloud AI later can still surface it.
                appState.announcements.current = nil
            } else if appState.auth.isSignedIn {
                Task { await appState.announcements.fetchPending() }
            }
        }
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.sidebarHidden ? .detailOnly : .all },
            set: { appState.sidebarHidden = ($0 == .detailOnly) }
        )
    }

    private func background(for portrait: Portrait) -> BackgroundPreset? {
        if let id = portrait.backgroundPresetID,
           let bg = backgrounds.first(where: { $0.id == id }) {
            return bg
        }
        return backgrounds.first(where: { $0.isDefault }) ?? backgrounds.first
    }

    private func deleteSelection() {
        let selected = portraits.filter { appState.selectedPortraitIDs.contains($0.id) }
        PortraitLibrary.delete(
            selected,
            context: context,
            appState: appState,
            undoManager: undoManager
        )
    }
}

/// Detail-pane surface shown when the sidebar has more than one row selected.
/// Replaces the import drop zone with a thumbnail grid of the chosen portraits
/// so the selection is always reflected in the main view, not just the sidebar.
struct MultiSelectionView: View {
    let portraits: [Portrait]
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @Query private var backgrounds: [BackgroundPreset]

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]

    /// Order the grid by the sidebar order (most-recently-updated first).
    private var sortedPortraits: [Portrait] {
        portraits.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Loc.portraitsSelected(portraits.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(sortedPortraits) { portrait in
                        Cell(portrait: portrait, background: background(for: portrait))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.selectedPortraitIDs = [portrait.id]
                            }
                            .onDrag {
                                PortraitDragExport.itemProvider(
                                    primary: portrait,
                                    selected: sortedPortraits,
                                    backgroundResolver: { background(for: $0) },
                                    appState: appState
                                )
                            }
                            .contextMenu {
                                Button(Loc.export) {
                                    appState.libraryExportPortraitIDs = [portrait.id]
                                }
                                Divider()
                                Button(Loc.delete, role: .destructive) {
                                    PortraitLibrary.delete(
                                        [portrait],
                                        context: context,
                                        appState: appState,
                                        undoManager: undoManager
                                    )
                                }
                            }
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appCanvas)
        .contextMenu {
            Button("\(Loc.export) \(portraits.count) \(Loc.portraitsPlural)") {
                appState.libraryExportPortraitIDs = Set(portraits.map(\.id))
            }
            Divider()
            Button("\(Loc.delete) \(portraits.count) \(Loc.portraitsPlural)", role: .destructive) {
                PortraitLibrary.delete(
                    portraits,
                    context: context,
                    appState: appState,
                    undoManager: undoManager
                )
            }
        }
    }

    private func background(for portrait: Portrait) -> BackgroundPreset? {
        if let id = portrait.backgroundPresetID,
           let bg = backgrounds.first(where: { $0.id == id }) {
            return bg
        }
        return backgrounds.first(where: { $0.isDefault }) ?? backgrounds.first
    }

    private struct Cell: View {
        let portrait: Portrait
        let background: BackgroundPreset?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                CanvasPreview(portrait: portrait, background: background)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                Text(portrait.name.isEmpty ? Loc.unnamed : portrait.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
        }
    }
}
