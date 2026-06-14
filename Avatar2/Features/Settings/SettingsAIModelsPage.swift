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
//   "8 GB RAM" uit het frame blijft: elke ondersteunde Mac haalt dat.

import AvatarKit
import AvatarUI
import SwiftUI

struct SettingsAIModelsPage: View {
    /// E15.5: dev-detectie voor de Advanced-sectie.
    var entitlement: EntitlementModel?

    @State private var prefs = PrivacyPreferences2.shared
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
                onlineModelsCard
                localModelsCard
                // E15.6: generatie-modelkeuze (nano / OpenAI), alle gebruikers.
                generationModelCard
                // E15.5: alléén voor dev-accounts.
                if entitlement?.isDevUnlimited == true {
                    advancedCard
                }
            }
            .padding(.top, DSSpacing.gap8)

            Spacer()
        }
        .padding(.top, 76)
        .padding(.leading, DSSpacing.gap6)
        .padding(.trailing, DSSpacing.gap6)
        .task { model.refreshInstalledState() }
    }

    // MARK: Generation model (E15.6, user-facing nano / OpenAI)

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
        let isSelected = generationModel == option
        return Button {
            generationModel = option
            GenerationModelStore.shared.current = option
        } label: {
            HStack(spacing: DSSpacing.gap3) {
                VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
                    Text(option.label)
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.primary)
                    Text(option.detail)
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                }
                Spacer(minLength: DSSpacing.gap4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isSelected ? DSColor.Action.primary : DSColor.Foreground.muted)
            }
            .padding(DSSpacing.gap3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DSColor.Background.neutral : .clear)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    optionChip("Apple Vision", selected: prefs.engine == .appleVision) {
                        prefs.engine = .appleVision
                    }
                    optionChip("High-fidelity", selected: prefs.engine == .downloadedModel) {
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
                    Text("Leeg = productie. Herstart de app om een wijziging toe te passen.")
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
        Button(action: action) {
            Text(text)
                .dsTextStyle(.labelSmall)
                .foregroundStyle(selected ? DSColor.Action.onAction : DSColor.Foreground.primary)
                .lineLimit(1)
                .padding(.horizontal, DSSpacing.gap3)
                .frame(height: 30)
                .background(selected ? DSColor.Action.primary : DSColor.Background.neutral)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Allow online models (frame "row-system-audio", h94)

    private var onlineModelsCard: some View {
        HStack(spacing: DSSpacing.gap3) {
            Circle()
                .fill(DSColor.Background.action)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DSColor.Action.onAction)
                }
            VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
                Text("Allow online models")
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("This will give you more advanced editing features")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            Spacer(minLength: DSSpacing.gap4)
            DSToggle(isOn: Binding(
                get: { prefs.mode == .cloudAllowed },
                set: { prefs.mode = $0 ? .cloudAllowed : .localOnly }
            ))
        }
        .padding(DSSpacing.gap6)
        .frame(maxWidth: 608, alignment: .leading)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }

    // MARK: Local models (frame "list")

    private var localModelsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Local models")
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)

            HStack(spacing: DSSpacing.gap3) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DSSpacing.gap2) {
                        Text("Cut out")
                            .dsTextStyle(.labelBase)
                            .foregroundStyle(DSColor.Foreground.primary)
                        Text("•")
                            .dsTextStyle(.bodySmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                        Text("High-fidelity edges")
                            .dsTextStyle(.bodySmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                        Text("•")
                            .dsTextStyle(.bodySmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                        Text("8 GB RAM")
                            .dsTextStyle(.bodySmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                    }
                    subtitleLine
                }
                Spacer(minLength: DSSpacing.gap4)
                trailingControls
            }
            .padding(.top, DSSpacing.gap6)
        }
        .padding(DSSpacing.gap6)
        .frame(maxWidth: 608, alignment: .leading)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }

    @ViewBuilder
    private var subtitleLine: some View {
        switch model.phase {
        case .downloading(let fraction):
            // Downloadvoortgang (E04.6/E15.2-besluit: zichtbaar in deze
            // kaart, ook wanneer de download in onboarding gestart is —
            // zelfde store, dus zodra E04.6 bestaat deelt hij deze state).
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
            .frame(minHeight: 20)
        case .failed:
            Text("Download failed — check your connection and try again")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
        case .idle, .installed:
            Text("78 MB")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        switch model.phase {
        case .installed:
            HStack(spacing: DSSpacing.gap2) {
                if prefs.engine == .downloadedModel {
                    Text("Active")
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Action.primary)
                }
                DSIconButton(Image(systemName: "trash")) {
                    model.delete()
                    prefs.engine = .appleVision
                }
                .accessibilityLabel("Delete model")
            }
        case .downloading:
            ProgressView()
                .controlSize(.small)
        case .idle, .failed:
            DSIconButton(Image(systemName: "arrow.down.circle")) {
                model.download { prefs.engine = .downloadedModel }
            }
            .accessibilityLabel("Download model")
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
