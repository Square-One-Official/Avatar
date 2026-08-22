import SwiftUI
import SwiftData
import AppKit
#if !APP_STORE
import Sparkle
#endif

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedSettingsTab) {
            GeneralSettings()
                .tabItem { Label(Loc.settingsGeneral, systemImage: "gearshape") }
                .tag(SettingsTab.general)
            BackgroundsSettings()
                .tabItem { Label(Loc.backgrounds, systemImage: "photo.on.rectangle") }
                .tag(SettingsTab.backgrounds)
            AccountSettings()
                .tabItem { Label(Loc.settingsAccount, systemImage: "person.crop.circle") }
                .tag(SettingsTab.account)
        }
        .frame(width: 640, height: 460)
        .padding()
        .background(Color.appCanvas)
        .background(WindowBackgroundPainter(colorScheme: colorScheme).frame(width: 0, height: 0))
        .onAppear {
            appState.selectedSettingsTab = .general
        }
        // SwiftUI keeps the Settings view alive between Cmd+, presses, so
        // onAppear only fires once. Reset the tab whenever the window becomes
        // key so re-opening always lands on General.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            appState.selectedSettingsTab = .general
        }
        // Dedicated boolean keeps the Settings sheet separate from the main
        // window's. Sharing one flag let MainWindow's `.sheet()` steal focus,
        // which auto-dismisses macOS preferences panes.
        .sheet(isPresented: $appState.showProUpgradeSheetInSettings) {
            ProUpgradeSheet()
                .environment(appState)
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AppearanceSection()
                Divider()
                LanguageSection()
                Divider()
                PrivacyAndAISection()
                Divider()
                MagicCutoutSection()
                Divider()
                LibrarySection()
                #if !APP_STORE
                Divider()
                UpdatesSection()
                #endif
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Privacy & AI

/// Mirrors the onboarding choice and lets the user revisit it without
/// re-running the sheet. Mode toggles between `localOnly` (no photo
/// bytes leave the Mac, cloud features hidden) and `cloudAllowed`
/// (today's behaviour). When `localOnly`, exposes the engine picker
/// (Apple Vision vs downloaded model) plus the `DownloadedModelStatusView`
/// below it, which surfaces the download/remove/progress controls for
/// the matting model when the user picks that engine.
private struct PrivacyAndAISection: View {
    @Environment(PrivacyPreferences.self) private var prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Loc.privacyAndAITitle).font(.headline)
            Text(Loc.privacyAndAIDesc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Mode picker — segmented for fast switching.
            HStack(alignment: .center, spacing: 12) {
                Text(Loc.privacyModePickerLabel)
                    .frame(width: 70, alignment: .leading)
                Picker(Loc.privacyModePickerLabel, selection: Binding(
                    get: { prefs.mode },
                    set: { prefs.mode = $0 }
                )) {
                    Text(Loc.onboardingPrivacyLocalTitle).tag(AIPrivacyMode.localOnly)
                    Text(Loc.onboardingPrivacyCloudTitle).tag(AIPrivacyMode.cloudAllowed)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Engine picker, only visible in local-only mode.
            if prefs.mode == .localOnly {
                HStack(alignment: .center, spacing: 12) {
                    Text(Loc.privacyEnginePickerLabel)
                        .frame(width: 70, alignment: .leading)
                    Picker(Loc.privacyEnginePickerLabel, selection: Binding(
                        get: { prefs.engine },
                        set: { prefs.engine = $0 }
                    )) {
                        Text(Loc.onboardingEngineAppleVisionTitle).tag(LocalCutoutEngine.appleVision)
                        Text(Loc.onboardingEngineDownloadedTitle).tag(LocalCutoutEngine.downloadedModel)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if prefs.engine == .downloadedModel {
                    DownloadedModelStatusView()
                }
            }

            // `shareAnonymousDiagnostics` stays persisted for a future
            // telemetry surface (audit MEDIUM #27) but has no consumer
            // today — hiding the toggle avoids a Privacy control that
            // changes nothing.
        }
    }
}

/// Status / action row for the downloadable matting model (currently
/// ORMBG; see `ModelManager` for the model history).
/// Renders the right affordance for each `LocalModelState`:
///
///  - `.notDownloaded` → "Download" button + size estimate.
///  - `.downloading`   → progress bar + cancel.
///  - `.ready`         → "Downloaded" badge + Remove button.
///  - `.failed`        → error message + Try Again button.
///
/// Lives inside `PrivacyAndAISection` so it inherits the same disabled-
/// when-locked semantics; here it's only shown when mode == .localOnly,
/// so no extra locking is needed.
private struct DownloadedModelStatusView: View {
    @Environment(ModelManager.self) private var manager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch manager.state {
            case .notDownloaded:
                HStack(spacing: 10) {
                    Button {
                        manager.download()
                    } label: {
                        Label(Loc.modelDownloadButton, systemImage: "arrow.down.circle")
                    }
                    .controlSize(.regular)
                    Text(Loc.modelDownloadSizeHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    HStack {
                        Text(Loc.modelDownloadingLabel(percent: Int(progress * 100)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(Loc.cancel) {
                            manager.removeDownloaded()
                        }
                        .controlSize(.small)
                    }
                }

            case .ready:
                HStack(spacing: 10) {
                    Label(Loc.modelDownloadedReady, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.appSuccessInk)
                    Spacer()
                    Button(Loc.modelRemoveButton) {
                        manager.removeDownloaded()
                    }
                    .controlSize(.small)
                }

            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.appWarningInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.appWarning.opacity(0.30))
                        )
                    HStack {
                        Spacer()
                        Button(Loc.modelDownloadRetryButton) {
                            manager.download(force: true)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

// MARK: - Library back-up (export / import)

private struct LibrarySection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var portraits: [Portrait]
    @Query private var backgrounds: [BackgroundPreset]

    @State private var pendingPreview: LibraryArchive.ImportPreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Loc.librarySectionTitle).font(.headline)
            Text(Loc.librarySectionDesc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    runExport()
                } label: {
                    Label(Loc.libraryExportButton, systemImage: "square.and.arrow.up")
                }
                .disabled(portraits.isEmpty)

                Button {
                    runImport()
                } label: {
                    Label(Loc.libraryImportButton, systemImage: "square.and.arrow.down")
                }

                Spacer()
            }
        }
        .sheet(item: $pendingPreview) { preview in
            LibraryImportSheet(preview: preview)
                .environment(appState)
        }
    }

    private func runExport() {
        guard !portraits.isEmpty else {
            appState.note(Loc.libraryExportEmpty)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        let date = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "\(Loc.libraryExportFilenamePrefix) \(date).zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try LibraryArchive.export(portraits: portraits,
                                       backgrounds: backgrounds,
                                       to: url)
            appState.note(Loc.libraryExportSuccess(portraits.count))
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            appState.fail(Loc.libraryExportFailed(msg))
        }
    }

    private func runImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingPreview = try LibraryArchive.preview(from: url, context: context)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            appState.fail(Loc.libraryImportFailed(msg))
        }
    }
}

private struct AppearanceSection: View {
    @AppStorage("appearanceMode") private var appearanceRaw: String = AppearanceMode.dark.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Loc.appearance).font(.headline)
            Text(Loc.appearanceDesc)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(Loc.appearance, selection: Binding(
                get: { AppearanceMode(rawValue: appearanceRaw) ?? .dark },
                set: { appearanceRaw = $0.rawValue }
            )) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

private struct LanguageSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Loc.language).font(.headline)
            Text(Loc.languageDesc)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(Loc.language, selection: Binding(
                get: { appState.language },
                set: { appState.language = $0 }
            )) {
                ForEach(Lang.allCases) { lang in
                    Text(lang.label).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

private struct MagicCutoutSection: View {
    // Bound directly to UserDefaults via @AppStorage instead of going
    // through `MagicCutoutPreferences`. The prefs object exposes `enabled`
    // as a plain computed property over UserDefaults, which `@Observable`
    // does not track — so a binding through `prefs.enabled` writes
    // through but never re-renders the toggle. @AppStorage observes the
    // same key directly, which is what makes the switch follow clicks.
    @AppStorage("magicCutoutEnabled") private var enabled: Bool = true
    @Environment(AppState.self) private var appState
    @Environment(PrivacyPreferences.self) private var privacyPrefs

    /// Local-only already chose "no photos leave the Mac"; showing a
    /// greyed Pro upsell here reads as a paywall, not a privacy choice.
    private var lockedByPrivacy: Bool { !privacyPrefs.cloudAllowed }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Loc.magicCutoutTitle).font(.headline)

            if lockedByPrivacy {
                Text(Loc.magicCutoutLocalOnlySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(Loc.enableCloudAIInPrivacySettings) {
                    privacyPrefs.mode = .cloudAllowed
                }
                .controlSize(.regular)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(Loc.magicCutoutSubtitle)
                                .font(.body.weight(.medium))
                            if !appState.proEntitlement.isPro {
                                Text(Loc.magicCutoutProBadge)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.tint))
                            }
                        }
                        Text(Loc.magicCutoutDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Toggle(Loc.magicCutoutSubtitle, isOn: Binding(
                        get: { appState.proEntitlement.isPro && enabled },
                        set: { newValue in
                            if appState.proEntitlement.isPro {
                                enabled = newValue
                            } else if newValue {
                                appState.pendingMagicCutoutEnable = true
                                appState.showProUpgradeSheetInSettings = true
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(Loc.magicCutoutSubtitle)
                }
            }
        }
    }
}

#if !APP_STORE
private struct UpdatesSection: View {
    @Environment(UpdateManager.self) private var updater

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    var body: some View {
        @Bindable var updater = updater

        VStack(alignment: .leading, spacing: 8) {
            Text(Loc.updates).font(.headline)

            HStack {
                Text(Loc.currentVersion)
                Spacer()
                Text("\(appVersion) (\(buildNumber))")
                    .foregroundStyle(.secondary)
            }

            Toggle(Loc.autoCheckUpdates, isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }
            ))

            HStack {
                Button(Loc.checkNow) {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)

                Spacer()

                if let date = updater.lastUpdateCheckDate {
                    Text(Loc.lastChecked(date.formatted(.relative(presentation: .named))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if case .readyToRelaunch(let version) = updater.state {
                HStack {
                    Label(Loc.versionReady(version),
                          systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(.tint)
                    Spacer()
                    Button(Loc.relaunch) {
                        updater.relaunchAndInstall()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }
}
#endif

// MARK: - Backgrounds

struct BackgroundsSettings: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query(sort: \BackgroundPreset.createdAt) private var backgrounds: [BackgroundPreset]
    @State private var newColor = Color(.sRGB, red: 0.93, green: 0.95, blue: 0.97, opacity: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Loc.backgrounds).font(.headline)
                Spacer()
                Button {
                    addImage()
                } label: { Label(Loc.addImage, systemImage: "photo.badge.plus") }
                ColorPicker("", selection: $newColor, supportsOpacity: false)
                    .labelsHidden()
                Button(Loc.addColor) { addColor() }
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                    ForEach(backgrounds) { bg in
                        BackgroundSettingsCard(preset: bg)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func addImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            let name = url.deletingPathExtension().lastPathComponent
            let bg = BackgroundPreset(name: name, kind: .image, imageData: data)
            context.insert(bg)
            try? context.save()
        }
    }

    private func addColor() {
        let ns = NSColor(newColor).usingColorSpace(.sRGB) ?? .white
        let bg = BackgroundPreset(
            name: Loc.color,
            kind: .color,
            color: (Double(ns.redComponent), Double(ns.greenComponent),
                    Double(ns.blueComponent), Double(ns.alphaComponent))
        )
        context.insert(bg)
        try? context.save()
    }
}

private struct BackgroundSettingsCard: View {
    @Bindable var preset: BackgroundPreset
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var allBackgrounds: [BackgroundPreset]

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if preset.kind == .image, let img = appState.backgroundImage(for: preset) {
                    Image(img, scale: 1, label: Text(""))
                        .resizable()
                        .scaledToFill()
                } else {
                    let c = preset.colorComponents
                    Color(.sRGB, red: c.0, green: c.1, blue: c.2, opacity: c.3)
                }
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(preset.isDefault ? Color.accentColor : Color.secondary.opacity(0.3),
                                  lineWidth: preset.isDefault ? 2 : 1)
            }

            TextField(Loc.name, text: $preset.name)
                .textFieldStyle(.plain)
                .font(.caption)
                .multilineTextAlignment(.center)
                .onChange(of: preset.name) { _, _ in try? context.save() }

            HStack(spacing: 6) {
                Button {
                    setDefault()
                } label: {
                    Image(systemName: preset.isDefault ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .help(Loc.setAsDefault)
                .accessibilityLabel(Loc.setAsDefault)

                Button {
                    context.delete(preset)
                    try? context.save()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(preset.isDefault)
                .accessibilityLabel(Loc.delete)
            }
            .font(.caption)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.appSurface)
        )
        .contextMenu {
            Button(Loc.setAsDefault) { setDefault() }
            Divider()
            Button(Loc.delete, role: .destructive) {
                guard !preset.isDefault else { return }
                context.delete(preset)
                try? context.save()
            }
            .disabled(preset.isDefault)
        }
    }

    private func setDefault() {
        for bg in allBackgrounds { bg.isDefault = false }
        preset.isDefault = true
        try? context.save()
    }
}

// MARK: - Account

struct AccountSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if appState.auth.isSignedIn, let email = appState.auth.email {
                    profileCard(email: email)
                    if appState.proEntitlement.isPro {
                        creditsCard
                    } else {
                        upgradeCard
                    }
                } else {
                    GroupBox { signedOutProfile }
                    if appState.proEntitlement.needsAccountLink {
                        LinkDeviceCard()
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }

    private func avatarCircle(for email: String) -> some View {
        let initial = email.first.map { String($0).uppercased() } ?? "?"
        return ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 0.55, green: 0.40, blue: 0.95),
                             Color(red: 0.40, green: 0.55, blue: 0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text(initial)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 64, height: 64)
    }

    // MARK: Profile card (identity)

    @ViewBuilder
    private func profileCard(email: String) -> some View {
        GroupBox {
            HStack(alignment: .center, spacing: 16) {
                avatarCircle(for: email)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(email)
                            .font(.body.weight(.medium))
                        if appState.proEntitlement.isPro {
                            Text(Loc.proPlanName)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.tint))
                        }
                    }
                    Text(Loc.accountEmailFromGoogle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(Loc.proSignOut) {
                    appState.auth.signOut()
                    appState.proEntitlement.clear()
                }
                .controlSize(.small)
            }
            .padding(8)
        }
    }

    // MARK: Credits / balance card (Pro only)

    @ViewBuilder
    private var creditsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Loc.creditsBalanceTitle)
                        .font(.headline)
                    Text(Loc.creditsBalanceDesc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Loc.creditsCount(appState.proEntitlement.credits))
                            .font(.title2.weight(.semibold))
                        Text(Loc.creditsBalanceLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let renews = appState.proEntitlement.monthlyResetAt {
                            Text(Loc.creditsResetOn(renews.formatted(date: .abbreviated, time: .omitted)))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    Button(Loc.buyMoreCredits) {
                        Task { await buyTopup() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()
                HStack {
                    Spacer()
                    Button(Loc.proManageSubscription) {
                        Task { await openPortal() }
                    }
                    .controlSize(.small)
                }
            }
            .padding(8)
        }
    }

    // MARK: Upgrade card (signed in, not Pro)

    @ViewBuilder
    private var upgradeCard: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Loc.proSectionTitle)
                        .font(.headline)
                    Text(Loc.proSectionSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(Loc.proUpgradeNow) {
                    appState.showProUpgradeSheetInSettings = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private var signedOutProfile: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Loc.accountNotSignedIn).font(.body.weight(.medium))
                    Text(Loc.accountSignInRationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let err = appState.auth.lastSignInError {
                StatusChip(severity: .danger, message: err, style: .soft)
            }
            HStack {
                Spacer()
                Button {
                    appState.auth.startSignIn()
                } label: {
                    Label(Loc.proSignInWithGoogle, systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(8)
    }

    @MainActor
    private func openPortal() async {
        do {
            let url = try await appState.backend.openPortal()
            NSWorkspace.shared.open(url)
        } catch let err as BackendError {
            appState.report(err)
        } catch {
            appState.fail((error as? LocalizedError)?.errorDescription ?? Loc.somethingWentWrong)
        }
    }

    @MainActor
    private func buyTopup() async {
        do {
            switch try await appState.backend.topup(pack: .credits200) {
            case .web(let url):
                NSWorkspace.shared.open(url)
            case .storeKit:
                throw BackendError.decode
            }
        } catch let err as BackendError {
            appState.report(err)
        } catch {
            appState.fail((error as? LocalizedError)?.errorDescription ?? Loc.somethingWentWrong)
        }
    }
}

/// "Pro is active on this Mac" card — surfaced in Account settings when
/// the user paid via the pre-auth (anonymous) checkout flow but hasn't
/// signed in yet. Tapping the CTA emails a Supabase magic-link to the
/// address Stripe captured at checkout, which deep-links back into the
/// app and binds Pro to a Supabase account so it survives reinstall and
/// can sync to additional Macs. Sole entry point — the older sidebar
/// banner was removed as permanent visual noise.
private struct LinkDeviceCard: View {
    @Environment(AppState.self) private var appState
    @State private var sending: Bool = false
    @State private var feedback: Feedback?

    private enum Feedback: Equatable {
        case success(email: String)
        case failure
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Loc.syncBannerTitle)
                            .font(.body.weight(.medium))
                        if let email = appState.proEntitlement.linkEmail {
                            Text(Loc.syncBannerBody(email: email))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if let feedback {
                    feedbackChip(feedback)
                }

                HStack {
                    Spacer()
                    Button {
                        Task { await sendLink() }
                    } label: {
                        HStack(spacing: 6) {
                            if sending { ProgressView().controlSize(.mini) }
                            Text(Loc.syncBannerSendLink)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(sending)
                }
            }
            .padding(8)
        }
        .motionAwareAnimation(.easeOut(duration: 0.18), value: feedback)
    }

    @ViewBuilder
    private func feedbackChip(_ feedback: Feedback) -> some View {
        switch feedback {
        case .success(let email):
            StatusChip(severity: .success,
                       message: Loc.syncBannerLinkSent(email: email),
                       style: .soft)
        case .failure:
            StatusChip(severity: .danger,
                       message: Loc.syncBannerSendFailed,
                       style: .soft)
        }
    }

    private func sendLink() async {
        if sending { return }
        sending = true
        defer { sending = false }
        do {
            let email = try await appState.backend.resendMagicLink()
            feedback = .success(email: email ?? appState.proEntitlement.linkEmail ?? "")
        } catch {
            feedback = .failure
        }
    }
}

