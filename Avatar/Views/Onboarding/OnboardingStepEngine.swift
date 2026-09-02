import SwiftUI

/// Step 3 — local cutout engine. Only shown when the user picked
/// `localOnly` in step 2. Two cards: Apple Vision (default, always
/// available) and the downloaded ORMBG matting model (~78 MB).
///
/// UX shape:
///  - Selecting "Download enhanced model" auto-triggers the download
///    (so the user doesn't have to hunt for a separate button).
///  - Progress bar renders inline below the cards while the download
///    runs — Done is disabled in that state, with the button label
///    showing live percent so the user knows the sheet hasn't frozen.
///  - When the model is ready, Done re-enables with its normal label.
///  - When the download fails, Done becomes "Continue without enhanced
///    model" — clicking it flips the engine back to Apple Vision and
///    dismisses, so the user is never stuck because of a network blip.
///  - When the user picks Apple Vision, Done is always enabled
///    immediately; no download work is performed.
///
/// The download itself is owned by `ModelManager` (a singleton on
/// `AppState`), so dismissing the sheet mid-flight doesn't kill it —
/// progress continues in the background and the Settings → Privacy &
/// AI engine row picks up the same state machine. That's deliberate:
/// nothing in this view "owns" the download, we're just a face for it.
struct OnboardingStepEngine: View {
    @Environment(PrivacyPreferences.self) private var prefs
    @Environment(ModelManager.self) private var manager

    /// Called when the user clicks Done. Host marks onboarding complete
    /// and dismisses. Engine selection is already in `prefs` by then.
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Loc.onboardingEngineTitle)
                    .font(.title2.weight(.semibold))
                Text(Loc.onboardingEngineBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 18)

            VStack(spacing: 10) {
                ChoiceCard(
                    isSelected: prefs.engine == .appleVision,
                    title: Loc.onboardingEngineAppleVisionTitle,
                    badge: Loc.onboardingEngineAppleVisionDefault,
                    detail: Loc.onboardingEngineAppleVisionBody,
                    icon: "applelogo",
                    position: (1, 2)
                ) {
                    prefs.engine = .appleVision
                }
                ChoiceCard(
                    isSelected: prefs.engine == .downloadedModel,
                    title: Loc.onboardingEngineDownloadedTitle,
                    badge: nil,
                    detail: Loc.onboardingEngineDownloadedBody,
                    icon: "arrow.down.circle",
                    position: (2, 2)
                ) {
                    prefs.engine = .downloadedModel
                    // Auto-trigger the download on first selection. No-op
                    // if a download is already in progress or the model is
                    // already cached — `download()` guards both cases.
                    manager.download()
                }
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Loc.onboardingEngineTitle)
            .focusable()
            .onMoveCommand { direction in
                switch direction {
                case .up:
                    prefs.engine = .appleVision
                case .down:
                    prefs.engine = .downloadedModel
                    manager.download()
                default:
                    break
                }
            }

            // Inline download status. Hidden when the user is on Apple
            // Vision (state is irrelevant) AND when the engine is
            // downloaded but the download hasn't started yet
            // (`.notDownloaded` would normally fire just before the auto-
            // trigger lands; reserving the row keeps the layout from
            // jumping when state flips to `.downloading`).
            if prefs.engine == .downloadedModel {
                downloadStatusRow
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .transition(.opacity)
            }

            Button(action: onDoneTapped) {
                Text(doneButtonLabel)
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(doneButtonEnabled ? Color.appBrandSolid : Color.appBrandSolid.opacity(0.45))
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!doneButtonEnabled)
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 4)
            .keyboardShortcut(.defaultAction)
        }
        .motionAwareAnimation(.easeOut(duration: 0.18), value: stateIdentity)
    }

    // MARK: - Inline status row

    @ViewBuilder
    private var downloadStatusRow: some View {
        switch manager.state {
        case .notDownloaded:
            // Transient — the auto-trigger fires the moment the user
            // picks the card, so we usually flip to `.downloading` on
            // the next runloop tick. Render a placeholder bar at 0 so
            // the layout doesn't pop in.
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: 0)
                    .progressViewStyle(.linear)
                Text(Loc.modelDownloadingLabel(percent: 0))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text(Loc.modelDownloadingLabel(percent: Int(progress * 100)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            Label(Loc.modelDownloadedReady, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(Color.appSuccessInk)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                Button(Loc.modelDownloadRetryButton) {
                    manager.download(force: true)
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Done button state machine

    /// True when the Done button should be tappable. Apple Vision is
    /// always allowed; downloaded-model path waits for the download to
    /// either finish or fail (failure path falls back to Apple Vision).
    /// `.notDownloaded` keeps Done disabled so a click in the gap
    /// between card-tap and download-start cannot exit with a missing model.
    private var doneButtonEnabled: Bool {
        switch (prefs.engine, manager.state) {
        case (.appleVision, _):
            return true
        case (.downloadedModel, .ready),
             (.downloadedModel, .failed):
            return true
        case (.downloadedModel, .notDownloaded),
             (.downloadedModel, .downloading):
            return false
        }
    }

    /// Label text matches the state. The failure path explicitly says
    /// "without enhanced model" so the user understands clicking Done
    /// silently falls back rather than installing a broken model.
    private var doneButtonLabel: String {
        switch (prefs.engine, manager.state) {
        case (.appleVision, _),
             (.downloadedModel, .ready):
            return Loc.onboardingDone
        case (.downloadedModel, .notDownloaded):
            return Loc.modelDownloadingLabel(percent: 0)
        case (.downloadedModel, .downloading(let progress)):
            return Loc.modelDownloadingLabel(percent: Int(progress * 100))
        case (.downloadedModel, .failed):
            return Loc.onboardingDoneWithoutEnhanced
        }
    }

    /// Click handler. Most paths just dismiss; the failure path also
    /// rewrites the engine to Apple Vision so the user lands in a
    /// coherent post-onboarding state (the cutout pipeline reads
    /// `prefs.engine`, and silently leaving it on `.downloadedModel`
    /// while there's no model on disk would loop the download UI in
    /// Settings on next launch).
    private func onDoneTapped() {
        if prefs.engine == .downloadedModel,
           case .failed = manager.state {
            prefs.engine = .appleVision
        }
        onDone()
    }

    /// Compound key for the `.animation(_:value:)` modifier so SwiftUI
    /// triggers the crossfade on every meaningful state change without
    /// fighting `LocalModelState`'s tuple of associated values.
    private var stateIdentity: String {
        switch manager.state {
        case .notDownloaded: return "n"
        case .downloading(let p): return "d\(Int(p * 100))"
        case .ready: return "r"
        case .failed: return "f"
        }
    }
}

// MARK: - Shared card view

/// Radio-card primitive used by both the privacy and engine steps. Selection
/// state is owned by the parent (writes the underlying preference); the
/// card just displays the current state and exposes a tap target. Keeping
/// this view stateless avoids the source-of-truth split where a `@State`
/// selection inside the card could drift from the persisted preference.
struct ChoiceCard: View {
    let isSelected: Bool
    let title: String
    /// Optional pill (e.g. "Recommended for privacy" / "Default") rendered
    /// next to the title. Set nil to omit.
    let badge: String?
    let detail: String
    let icon: String
    /// 1-based index and group size for VoiceOver ("1 of 2").
    let position: (index: Int, count: Int)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(isSelected ? Color.appBrand : .secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.secondary.opacity(0.15))
                                )
                                .accessibilityHidden(true)
                        }
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1)
                }

                Spacer(minLength: 0)

                // Radio indicator on the right keeps the eye on the choice
                // structure rather than buried inside the icon column.
                Circle()
                    .strokeBorder(isSelected ? Color.appBrand : Color.secondary.opacity(0.4),
                                   lineWidth: 1.5)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.appBrand : Color.clear)
                            .padding(4)
                    )
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.appBrand : Color.secondary.opacity(0.18),
                                           lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(isSelected ? Loc.onboardingChoiceSelected : Loc.onboardingChoiceNotSelected)
        .accessibilityHint(Loc.onboardingChoiceHint(position.index, of: position.count))
    }

    private var accessibilityName: String {
        if let badge {
            return "\(title), \(badge). \(detail)"
        }
        return "\(title). \(detail)"
    }
}
