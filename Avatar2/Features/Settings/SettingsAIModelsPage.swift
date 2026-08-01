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

import AvatarKit
import AvatarUI
import SwiftUI

struct SettingsAIModelsPage: View {
    /// E15.5: dev-detectie voor de Advanced-sectie.
    var entitlement: EntitlementModel?

    private let prefs = PrivacyPreferences2.shared
    @State private var model = HighFidelityModelState()
    /// E15.5: tick om de pickers te laten herrenderen na een keuze.
    @State private var overridesTick = 0
    /// E15.6: gebruikersgerichte generatie-modelkeuze (nano / OpenAI).
    @State private var generationModel = GenerationModelStore.shared.current
    /// E01.15: DEBUG backend-override (lokaal tegen Vercel-preview). Bindt
    /// direct op de UserDefaults-keys die BackendClient.resolveBaseURL leest.
    @AppStorage("dev.apiBase") private var devApiBase: String = ""
    @AppStorage("dev.vercelBypass") private var devVercelBypass: String = ""

    private let overrides = DevModelOverrides.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI & Models")
                .dsTextStyle(.h1)
                .foregroundStyle(DSColor.Foreground.primary)

            VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                privacyTierCard
                localModelsCard
                privacyFeatureMatrixCard
                if prefs.allowsThirdPartyCloud {
                    generationModelCard
                }
                // E15.5: alléén voor dev-accounts.
                if entitlement?.isDevUnlimited == true {
                    advancedCard
                }
            }
            .padding(.top, DSSpacing.gap8)
        }
        .padding(.top, ShellMetrics.settingsPageTopInset)
        .padding(.leading, DSSpacing.gap6)
        .padding(.trailing, DSSpacing.gap6)
        .task { model.refreshInstalledState() }
    }

    private var disabledTiers: Set<AIPrivacyTier> {
        AppleIntelligenceAvailability.supportsApplePrivateCloud ? [] : [.appleCloud]
    }

    // MARK: Privacy tier (Privacy Tier Picker)

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
                ),
                disabledTiers: disabledTiers
            )
            .padding(.top, DSSpacing.gap4)

            if AppleIntelligenceAvailability.supportsApplePrivateCloud {
                Text("Use the sparkle button in Background to generate images with Apple Intelligence.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .padding(.top, DSSpacing.gap3)
            }
        }
        .padding(DSSpacing.gap6)
        .frame(maxWidth: 608, alignment: .leading)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
        .refreshAppleIntelligenceAvailability {
            PrivacyPreferences2.shared.reapplyFingerprintPolicy()
        }
    }

    // MARK: Feature matrix

    private var privacyFeatureMatrixCard: some View {
        PrivacyFeatureMatrix()
            .padding(DSSpacing.gap6)
            .frame(maxWidth: 608, alignment: .leading)
            .background(DSColor.Background.card)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }

    // MARK: Generation model (E15.6, Advanced tier only)

    private var generationModelCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Generation model")
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)
            Text("Used for AI styles, clothing and hair")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)

            VStack(spacing: DSSpacing.gap2) {
                ForEach(GenerationModel.allCases) { option in
                    generationOptionRow(option)
                }
            }
            .padding(.top, DSSpacing.gap4)
        }
        .padding(DSSpacing.gap6)
        .frame(maxWidth: 608, alignment: .leading)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }

    private func generationOptionRow(_ option: GenerationModel) -> some View {
        SettingsCheckmarkRow(
            title: option.label,
            subtitle: option.detail,
            isSelected: generationModel == option
        ) {
            generationModel = option
            GenerationModelStore.shared.current = option
        }
    }

    // MARK: Advanced (E15.5, dev-only model-picker)

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DSSpacing.gap2) {
                Text("Advanced")
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                DSBadge("Dev only", type: .neutral)
            }

            VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                // Lokale cutout-engine (Vision / gedownload model) — chips
                // i.p.v. Menu (Menu's blokkeerden de first-render-window).
                pickerColumn(title: "Cut out engine (local)") {
                    optionChip("Regular quality", selected: prefs.engine == .appleVision) {
                        prefs.engine = .appleVision
                    }
                    optionChip("High quality", selected: prefs.engine == .downloadedModel) {
                        prefs.engine = .downloadedModel
                    }
                }
                // Per cloud-feature het override-model.
                ForEach(DevModelFeature.allCases, id: \.self) { feature in
                    pickerColumn(title: feature.label) {
                        let current = overrides.override(for: feature)
                        optionChip("Default", selected: current == nil) { setOverride(nil, feature) }
                        ForEach(feature.modelKeys, id: \.self) { key in
                            optionChip(key, selected: current == key) { setOverride(key, feature) }
                        }
                    }
                }
                // E01.15: backend-endpoint-override (lokaal tegen Vercel-preview).
                VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                    Text("Backend endpoint (dev)")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.subtle)
                    DSTextField(placeholder: "https://…preview.vercel.app", text: $devApiBase)
                    DSTextField(placeholder: "Vercel protection bypass secret", text: $devVercelBypass)
                    Text("Empty = production. Restart the app to apply a change.")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                }
            }
            .padding(.top, DSSpacing.gap4)
            .id(overridesTick)
        }
        .padding(DSSpacing.gap6)
        .frame(maxWidth: 608, alignment: .leading)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }

    private func setOverride(_ key: String?, _ feature: DevModelFeature) {
        overrides.setOverride(key, for: feature)
        overridesTick += 1
    }

    private func pickerColumn(title: String, @ViewBuilder chips: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            Text(title)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.subtle)
            HStack(spacing: DSSpacing.gap2) { chips() }
        }
    }

    private func optionChip(_ text: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        OptionChipButton(text: text, selected: selected, action: action)
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
                    ProgressView(value: fraction)
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
            ProgressView()
                .controlSize(.small)
        case .idle, .failed:
            DSIconButton(Image(systemName: "arrow.down.circle"), label: "Download model") {
                model.download { prefs.engine = .downloadedModel }
            }
        }
    }
}

private struct OptionChipButton: View {
    let text: String
    let selected: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var background: Color {
        if selected { return DSColor.Action.primary }
        if isHovering { return DSColor.Background.neutralStronger }
        return DSColor.Background.neutral
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .dsTextStyle(.labelSmall)
                .foregroundStyle(selected ? DSColor.Action.onAction : DSColor.Foreground.primary)
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.gap3)
                .frame(height: 30)
                .background(background)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 && !selected }
        .dsMotion(DSMotion.micro, value: isHovering)
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
