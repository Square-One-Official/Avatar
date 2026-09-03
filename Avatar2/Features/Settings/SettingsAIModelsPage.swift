// AI & Models-pagina (E15.2) — Figma 4019:823. Twee kaarten met 4pt
// tussenruimte: de online-modellen-toggle (zelfde PrivacyPreferences als
// onboarding/E04.3) en de Local models-lijst met de High-fidelity
// edges-kaart op OrmbgModelStore (E02.3) — dezelfde store als de
// onboarding-downloadstap (E04.6): één download-state, twee vensters.
//
// Frame-afwijkingen, gedocumenteerd:
// - header-tekstnode draagt nog "Preferences" (template-bug) → "AI & Models";
// - waveform-icoon is per het bord een placeholder → cloud-glyph;
// - modelnaam/grootte zijn echte waarden: High-fidelity edges, 78 MB
//   (manifest-zip; de ±175 MB uit figma-design-review.md klopte niet).
// - "8 GB RAM" uit het Figma-frame weggelaten: elke ondersteunde Mac haalt
//   dat; voegt geen keuze-informatie toe in Settings.
// - Figma toont drie privacy-rijen (On-device / Apple Private Cloud /
//   Advanced). Besluit Thierry 2026-09-02: twee keuzes, Local only / Cloud.

import AvatarKit
import AvatarUI
import SwiftUI

struct SettingsAIModelsPage: View {
    private let prefs = PrivacyPreferences2.shared
    @State private var model = HighFidelityModelState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI & Models")
                .dsTextStyle(.h1)
                .foregroundStyle(DSColor.Foreground.primary)

            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                privacyTierCard
                localModelsCard
                privacyFeatureMatrixCard
            }
            .padding(.top, DSSpacing.gap8)
        }
        .padding(.top, ShellMetrics.settingsPageTopInset)
        .padding(.leading, DSSpacing.gap6)
        .padding(.trailing, DSSpacing.gap6)
        .task { model.refreshInstalledState() }
    }

    // MARK: Privacy tier (Local only / Cloud)

    private var privacyTierCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI privacy")
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
            Text("Choose how far your photos travel for AI edits")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)

            PrivacyTierRadioGroup(
                selection: Binding(
                    get: { prefs.tier },
                    set: { prefs.tier = $0 }
                )
            )
            .padding(.top, DSSpacing.gap4)
        }
        .padding(DSSpacing.gap6)
        .frame(maxWidth: 608, alignment: .leading)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }

    // MARK: Feature matrix

    private var privacyFeatureMatrixCard: some View {
        PrivacyFeatureMatrix()
            .padding(DSSpacing.gap6)
            .frame(maxWidth: 608, alignment: .leading)
            .background(DSColor.Background.card)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }

    // MARK: Local models (frame "list")

    private static let modelSizeMB = 78

    private var localModelsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Local models")
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
            Text("Optional downloads for sharper on-device results")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)

            localModelRow
                .padding(.top, DSSpacing.gap4)
        }
        .padding(DSSpacing.gap6)
        .frame(maxWidth: 608, alignment: .leading)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }

    private var localModelRow: some View {
        HStack(spacing: DSSpacing.gap3) {
            RoundedRectangle(cornerRadius: DSRadius.md)
                .fill(DSColor.Background.neutral)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: DSIconSize.lg, weight: .medium))
                        .foregroundStyle(DSColor.Foreground.subtle)
                }

            VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
                Text("Remove background")
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                localModelSubtitle
            }

            Spacer(minLength: DSSpacing.gap4)
            trailingControls
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    @ViewBuilder
    private var localModelSubtitle: some View {
        switch model.phase {
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                Text("Downloading high-quality model")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                HStack(spacing: DSSpacing.gap2) {
                    DSProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(DSColor.Action.primary)
                        .frame(width: 160)
                    Text("\(Int(fraction * 100))%")
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .monospacedDigit()
                }
            }
        default:
            Text(localModelSubtitleText)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
        }
    }

    private var localModelSubtitleText: String {
        switch model.phase {
        case .failed:
            return "Download failed — check your connection and try again"
        case .installed where prefs.engine == .downloadedModel:
            return "High quality · sharper hair · \(Self.modelSizeMB) MB"
        case .installed:
            return "Installed · using built-in engine"
        case .idle, .downloading:
            return "Sharper hair edges · \(Self.modelSizeMB) MB download"
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        switch model.phase {
        case .installed:
            HStack(spacing: DSSpacing.gap3) {
                DSToggle(isOn: Binding(
                    get: { prefs.engine == .downloadedModel },
                    set: { prefs.engine = $0 ? .downloadedModel : .appleVision }
                ))
                .accessibilityLabel("Use High quality cutout model")
                DSIconButton(Image(systemName: "trash"), label: "Delete model") {
                    model.delete()
                    prefs.engine = .appleVision
                }
            }
        case .downloading:
            DSProgressView()
                .controlSize(.small)
        case .idle, .failed:
            DSIconButton(Image(systemName: "arrow.down.circle"), label: "Download model") {
                model.download { prefs.engine = .downloadedModel }
            }
        }
    }
}

/// UI-state rond OrmbgModelStore.shared. Geslaagde download activeert de
/// engine meteen (de gebruiker downloadde hem om hem te gebruiken) — de
/// trash-knop zet de keuze terug naar Apple Vision.
@MainActor
@Observable
final class HighFidelityModelState {
    enum Phase: Equatable {
        case idle
        case downloading(Double)
        case installed
        case failed
    }

    private(set) var phase: Phase = .idle

    private let store = OrmbgModelStore.shared

    func refreshInstalledState() {
        if case .downloading = phase { return }
        phase = store.installedModelURL() != nil ? .installed : .idle
    }

    func download(onInstalled: @escaping () -> Void) {
        guard phase != .installed else { return }
        phase = .downloading(0)
        Task {
            do {
                _ = try await store.download { fraction in
                    Task { @MainActor [weak self] in
                        if case .downloading = self?.phase {
                            self?.phase = .downloading(fraction)
                        }
                    }
                }
                phase = .installed
                onInstalled()
            } catch {
                phase = .failed
            }
        }
    }

    func delete() {
        phase = .idle
        Task {
            try? await store.removeInstalled()
        }
    }
}
