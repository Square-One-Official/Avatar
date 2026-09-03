// E42 — Compacte DS-popup voor AI-achtergrondgeneratie (Apple-achtige stappen).

import AvatarKit
import AvatarUI
import SwiftUI

enum GenerateBackgroundStep: Hashable {
    case style
    case view
}

struct GenerateBackgroundSheet: View {
    let context: BackgroundGenerationContext
    var entitlement: EntitlementModel?
    var applyAfterSave: Bool
    var onSaved: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    /// E42-audit (#11): formulier-state als één @Observable model i.p.v. 10 losse
    /// @State — kleiner body + testbare `canGenerate`/`usesCloudModel`.
    @State private var form: BackgroundGenerationForm

    init(
        context: BackgroundGenerationContext,
        entitlement: EntitlementModel?,
        applyAfterSave: Bool = true,
        onSaved: @escaping (Data) -> Void
    ) {
        self.context = context
        self.entitlement = entitlement
        self.applyAfterSave = applyAfterSave
        self.onSaved = onSaved
        _form = State(initialValue: BackgroundGenerationForm(model: .gemini))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, DSSpacing.gap5)
                .padding(.top, DSSpacing.gap5)
                .padding(.bottom, DSSpacing.gap3)

            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.gap3) {
                    stepsCard
                    promptBlock
                }
                .padding(.horizontal, DSSpacing.gap5)
            }
            .frame(maxHeight: 420)

            actionRow
                .padding(DSSpacing.gap5)
        }
        .frame(width: 400)
        .background(DSColor.Background.app)
        .appliedAppearancePreference()
        .onDisappear { form.coordinator.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1) {
            HStack {
                Text("Generate a background")
                    .dsTextStyle(.h4)
                    .foregroundStyle(DSColor.Foreground.primary)
                Spacer()
                DSIconButton(Image(systemName: "xmark"), label: "Close", size: .small) {
                    dismiss()
                }
                .disabled(form.isGenerating)
            }
            Text("\(context.contextHint)")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.subtle)
        }
    }

    // MARK: - Steps card

    private var stepsCard: some View {
        VStack(spacing: 0) {
            styleStep
            stepDivider
            viewStep
        }
        .dsPanelSurface(cornerRadius: DSRadius.xl2, solid: true)
    }

    private var stepDivider: some View {
        Divider().overlay(DSColor.Foreground.divider).padding(.leading, DSSpacing.gap3)
    }

    private var styleStep: some View {
        collapsibleStep(
            step: .style,
            icon: "photo.on.rectangle.angled",
            title: "Style",
            summary: form.style.label
        ) {
            styleGrid
            if form.style == .custom {
                DSTextField(placeholder: "Describe a style…", text: $form.customStyleText)
                    .disabled(form.isGenerating)
            }
        }
    }

    private var viewStep: some View {
        collapsibleStep(
            step: .view,
            icon: "viewfinder",
            title: "View",
            summary: form.selectedView.label
        ) {
            viewGrid
        }
    }

    private func collapsibleStep<Content: View>(
        step: GenerateBackgroundStep,
        icon: String,
        title: String,
        summary: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let isExpanded = form.expandedStep == step
        return VStack(spacing: 0) {
            Button {
                DSMotion.animate(DSMotion.fast) {
                    form.expandedStep = isExpanded ? nil : step
                }
            } label: {
                HStack(spacing: DSSpacing.gap2) {
                    stepIcon(icon)
                    Text(title)
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.muted)
                    Spacer(minLength: DSSpacing.gap2)
                    Text(summary)
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: DSIconSize.xxs, weight: .semibold))
                        .foregroundStyle(DSColor.Foreground.muted)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, DSSpacing.gap3)
                .padding(.vertical, DSSpacing.gap2_5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
            .disabled(form.isGenerating)

            if isExpanded {
                content()
                    .padding(.horizontal, DSSpacing.gap3)
                    .padding(.bottom, DSSpacing.gap2_5)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func stepIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: DSIconSize.xs, weight: .semibold))
            .foregroundStyle(DSColor.Foreground.muted)
            .frame(width: 16)
    }

    // MARK: - Grids (compact)

    private var styleGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.gap1_5), count: 4),
            spacing: DSSpacing.gap1_5
        ) {
            ForEach(BackgroundGenerationStyle.allCases) { item in
                styleCell(item)
            }
        }
    }

    private var viewGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.gap1_5), count: 5),
            spacing: DSSpacing.gap1_5
        ) {
            ForEach(BackgroundGenerationView.allCases) { item in
                viewCell(item)
            }
        }
    }

    private func styleCell(_ item: BackgroundGenerationStyle) -> some View {
        let selected = form.style == item
        return Button {
            form.style = item
        } label: {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .fill(styleGradient(item))
                    .frame(height: 40)
                    .overlay {
                        if item == .custom {
                            Image(systemName: "pencil")
                                .font(.system(size: DSIconSize.sm, weight: .semibold))
                                .foregroundStyle(DSColor.Foreground.subtle)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: DSRadius.md)
                            .strokeBorder(
                                selected ? DSColor.Action.primaryForeground : Color.clear,
                                lineWidth: DSBorderWidth.medium
                            )
                    }
                Text(item.label)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(selected ? DSColor.Foreground.primary : DSColor.Foreground.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .disabled(form.isGenerating)
    }

    private func viewCell(_ item: BackgroundGenerationView) -> some View {
        let selected = form.selectedView == item
        return Button {
            form.selectedView = item
        } label: {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .fill(DSColor.Background.neutral)
                    .frame(height: 32)
                    .overlay {
                        Text(item == .any ? "Any" : String(item.label.prefix(3)))
                            .dsTextStyle(.labelSmall)
                            .foregroundStyle(DSColor.Foreground.subtle)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: DSRadius.md)
                            .strokeBorder(
                                selected ? DSColor.Action.primaryForeground : Color.clear,
                                lineWidth: DSBorderWidth.medium
                            )
                    }
                Text(item.label)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(selected ? DSColor.Foreground.primary : DSColor.Foreground.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .buttonStyle(.plain)
        .dsFocusEffectDisabled()
        .disabled(form.isGenerating)
    }

    private func styleGradient(_ item: BackgroundGenerationStyle) -> LinearGradient {
        let colors = item.swatchColors
        return LinearGradient(
            colors: [BackgroundKit.rgb(colors.top), BackgroundKit.rgb(colors.bottom)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Prompt

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1_5) {
            DSTextField(
                placeholder: "Describe a background…",
                validation: form.errorMessage == nil ? .normal : .error,
                text: $form.prompt
            )
            .disabled(form.isGenerating)
            if let errorMessage = form.errorMessage {
                Text(errorMessage)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Signal.error)
            }
            HStack(spacing: DSSpacing.gap1) {
                DSPrivacyBadge(tier: .thirdParty)
                Text("\(context.creditCost) credits · processed securely online")
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        VStack(spacing: DSSpacing.gap2) {
            Text("May create unexpected results.")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.subtle)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DSSpacing.gap2) {
                DSNeutralButton("Cancel", fullWidth: true) {
                    dismiss()
                }
                .disabled(form.isGenerating)
                DSPrimaryButton(
                    form.isGenerating ? "Generating…" : "Generate",
                    fullWidth: true
                ) {
                    Task { await generate() }
                }
                .disabled(!form.canGenerate)
            }
        }
    }

    @MainActor
    private func generate() async {
        guard let entitlement else { return }

        guard entitlement.allowAIFeature(.backgroundGenerate) else { return }

        form.errorMessage = nil
        form.isGenerating = true
        defer { form.isGenerating = false }

        do {
            let raw = try await form.coordinator.generate(
                model: form.model,
                context: context,
                style: form.style,
                customStyleText: form.customStyleText,
                view: form.selectedView,
                prompt: form.prompt,
                entitlement: entitlement
            )
            guard let stored = form.coordinator.persistToLibrary(raw) else {
                form.errorMessage = "Couldn't save the image."
                return
            }
            onSaved(stored)
            await entitlement.refresh()
        } catch BackendError.noCredits {
            entitlement.handleOutOfCredits()
        } catch is CancellationError {
            return
        } catch BackgroundGenerationError.cancelled {
            return
        } catch {
            form.errorMessage = userFacingError(error)
            // The server charges on guaranteed delivery of the URL, so a failed
            // image download can still have spent a credit. Re-sync the balance
            // so the displayed count never lags behind the ledger.
            await entitlement.refresh()
        }
    }

    private func userFacingError(_ error: Error) -> String {
        if let backend = error as? BackendError {
            switch backend {
            case .rateLimited:
                return "Too many requests. Please wait a moment."
            case .server(504, _):
                return "Generation took too long. Try again."
            default:
                return backend.errorDescription ?? "Couldn't generate that background. Try a different description."
            }
        }
        return (error as? LocalizedError)?.errorDescription
            ?? "Couldn't generate that background. Try a different description."
    }
}

// MARK: - Form-state (#11)

/// E42-audit (#11): de bewerkbare formulier-state van de generate-sheet als
/// `@Observable` model i.p.v. losse `@State` op de view — kleiner view-body en
/// testbare `canGenerate`/`usesCloudModel`-logica. Puur UI-state (geen view-
/// dependencies); de acties (generate/apple-bridge) blijven op de view omdat ze
/// `entitlement`/`context`/`onSaved`/`dismiss` nodig hebben.
@MainActor
@Observable
final class BackgroundGenerationForm {
    var model: BackgroundGenerationModel
    var style: BackgroundGenerationStyle = .photorealistic
    var customStyleText = ""
    var selectedView: BackgroundGenerationView = .any
    var prompt = ""
    var isGenerating = false
    var errorMessage: String?
    var showApplePlayground = false
    var expandedStep: GenerateBackgroundStep?
    var modelMenuOpen = false
    let coordinator = BackgroundGenerationCoordinator()

    init(model: BackgroundGenerationModel) {
        self.model = model
    }

    var usesCloudModel: Bool { model == .gemini || model == .openAI }

    var canGenerate: Bool {
        guard !isGenerating else { return false }
        switch model {
        case .apple:
            return AppleIntelligenceAvailability.supportsApplePrivateCloud
        case .gemini, .openAI:
            return BackgroundGenerationCatalog.canGenerate(
                prompt: prompt, style: style, customStyleText: customStyleText
            )
        }
    }
}

// MARK: - Entrypoints (swatch + knop)

/// Gedeelde privacy-gate + presentatie voor de generate-entrypoints
/// (icon-swatch in het banner-paneel, gelabelde knop in het portret-paneel).
@MainActor
func presentGenerateBackground(
    context: BackgroundGenerationContext,
    entitlement: EntitlementModel?,
    applyAfterSave: Bool,
    onSaved: @escaping (Data) -> Void
) {
    guard let entitlement else { return }
    switch PrivacyPreferences2.shared.effectiveTier {
    case .onDevice:
        _ = entitlement.allowAIFeature(.backgroundGenerate, retry: {
            presentGenerateBackground(
                context: context,
                entitlement: entitlement,
                applyAfterSave: applyAfterSave,
                onSaved: onSaved
            )
        })
        return
    case .appleCloud, .thirdParty:
        guard entitlement.allowAIFeature(.backgroundGenerate) else { return }
    }
    GenerateBackgroundPresenter.shared.present(
        context: context,
        applyAfterSave: applyAfterSave,
        onSaved: onSaved
    )
}

struct GenerateBackgroundSwatch: View {
    let context: BackgroundGenerationContext
    var entitlement: EntitlementModel?
    var swatchSize: CGFloat = 36
    var applyAfterSave: Bool = true
    var onSaved: (Data) -> Void

    var body: some View {
        if BackgroundGenerationCatalog.hasGenerationPath {
            Button(action: openSheet) {
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .fill(DSColor.Background.neutral)
                    .frame(width: swatchSize, height: swatchSize)
                    .overlay { swatchIcon }
            }
            .buttonStyle(.plain)
            .dsFocusEffectDisabled()
            .dsHoverScale()
            .help("Generate a background")
            .cloudFeatureMuted()
        }
    }

    @ViewBuilder
    private var swatchIcon: some View {
        DSIcon(.privacyAdvanced, size: 14, weight: .bold)
            .foregroundStyle(DSColor.Foreground.subtle)
    }

    private func openSheet() {
        presentGenerateBackground(
            context: context, entitlement: entitlement,
            applyAfterSave: applyAfterSave, onSaved: onSaved
        )
    }
}

/// UX-audit background-paneel: generate als op-zichzelf-staande actie-knop —
/// een icon-tile tussen de kiesbare swatches leest als preset, niet als actie.
/// Vast sparkle-icoon (de privacy-tier-uitleg woont in de sheet zelf, niet in
/// het entrypoint-icoon).
struct GenerateBackgroundButton: View {
    let context: BackgroundGenerationContext
    var entitlement: EntitlementModel?
    var applyAfterSave: Bool = true
    var onSaved: (Data) -> Void

    var body: some View {
        if BackgroundGenerationCatalog.hasGenerationPath {
            DSNeutralButton(
                "Generate background",
                icon: Image(systemName: "sparkles"),
                size: .small,
                fullWidth: true
            ) {
                presentGenerateBackground(
                    context: context, entitlement: entitlement,
                    applyAfterSave: applyAfterSave, onSaved: onSaved
                )
            }
            .help("Generate a background with AI")
            .cloudFeatureMuted()
        }
    }
}
