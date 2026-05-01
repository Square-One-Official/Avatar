import SwiftUI
import SwiftData

struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query(sort: \Portrait.updatedAt, order: .reverse) private var portraits: [Portrait]
    @Query private var backgrounds: [BackgroundPreset]

    /// First-launch flag. Controls whether `WelcomeSignInSheet` should be
    /// presented over the main window. The sheet itself flips this true on
    /// either sign-in or "Maybe later" so the surface never reappears.
    @AppStorage("hasSeenWelcomeSignIn") private var hasSeenWelcomeSignIn = false
    /// Drives the `.sheet(isPresented:)` binding. Decoupled from
    /// `hasSeenWelcomeSignIn` so flipping the AppStorage during dismissal
    /// (e.g. on successful sign-in) doesn't fight the sheet's own dismiss
    /// transition.
    @State private var showWelcomeSheet = false

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            LibraryView(selection: $state.selectedPortraitID)
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
            .animation(.easeOut(duration: 0.22), value: state.proUpsellToast)
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if state.selectedPortraitID != nil {
                    Button {
                        pickFile()
                    } label: {
                        Label(Loc.importPhoto, systemImage: "plus")
                    }
                    .help(Loc.importPhotoHelp)
                }
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
        .sheet(isPresented: $showWelcomeSheet) {
            WelcomeSignInSheet()
                .environment(appState)
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
        .task {
            // Refresh Pro entitlement on launch so the badge/credits are accurate.
            // Supabase restores the keychain session asynchronously, so this
            // first call typically fires before `auth.isSignedIn` flips true —
            // the `onChange` below catches that transition and re-fires.
            appState.refreshEntitlement()
            // First-launch welcome. Sheet only presents if the user has
            // never seen it AND isn't already signed in (a returning user
            // who reinstalls and whose Keychain still holds a session
            // shouldn't be asked to sign in again).
            if !hasSeenWelcomeSignIn && !appState.auth.isSignedIn {
                showWelcomeSheet = true
            } else if !hasSeenWelcomeSignIn {
                hasSeenWelcomeSignIn = true
            }
        }
        .onChange(of: appState.auth.isSignedIn) { _, signedIn in
            if signedIn { appState.refreshEntitlement() }
        }
    }

    private func background(for portrait: Portrait) -> BackgroundPreset? {
        if let id = portrait.backgroundPresetID,
           let bg = backgrounds.first(where: { $0.id == id }) {
            return bg
        }
        return backgrounds.first(where: { $0.isDefault }) ?? backgrounds.first
    }

    private func pickFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            guard FreeTierGate.allowImport(incoming: 1,
                                           existingPortraitCount: portraits.count,
                                           appState: appState) else { return }
            ImportFlow.importFile(url: url, context: context, appState: appState)
        }
        #endif
    }
}

/// Detail-pane surface shown when the sidebar has more than one row selected.
/// Replaces the import drop zone with a thumbnail grid of the chosen portraits
/// so the selection is always reflected in the main view, not just the sidebar.
struct MultiSelectionView: View {
    let portraits: [Portrait]
    @Environment(AppState.self) private var appState
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
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(sortedPortraits) { portrait in
                        Cell(portrait: portrait, background: background(for: portrait))
                            .onTapGesture {
                                appState.selectedPortraitIDs = [portrait.id]
                            }
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appCanvas)
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
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
                Text(portrait.name.isEmpty ? Loc.unnamed : portrait.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
        }
    }
}
