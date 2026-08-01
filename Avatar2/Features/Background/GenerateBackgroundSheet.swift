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
        _form = State(initialValue: BackgroundGenerationForm(model: BackgroundGenerationCatalog.defaultModel()))
    }

    private var availableModels: [BackgroundGenerationModel] {
        BackgroundGenerationCatalog.availableModels()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, DSSpacing.gap5)
                .padding(.top, DSSpacing.gap5)
                .padding(.bottom, DSSpacing.gap3)

            if availableModels.isEmpty {
                emptyTierHint
                    .padding(.horizontal, DSSpacing.gap5)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.gap3) {
                        stepsCard
                        promptBlock
                    }
                    .padding(.horizontal, DSSpacing.gap5)
                }
                .frame(maxHeight: 420)
            }

            actionRow
                .padding(DSSpacing.gap5)
        }
        .frame(width: 400)
        .background(DSColor.Background.app)
        .appliedAppearancePreference()
        .onAppear { alignDefaultModel() }
        .onDisappear { form.coordinator.cancel() }
        .background { applePlaygroundBridge }
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

    private var emptyTierHint: some View {
        Text("Enable Apple Private Cloud or Advanced privacy in Settings to generate backgrounds.")
            .dsTextStyle(.bodySmall)
            .foregroundStyle(DSColor.Foreground.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Steps card

    private var stepsCard: some View {
        VStack(spacing: 0) {
            modelRow
            stepDivider
            styleStep
            stepDivider
            viewStep
        }
        .dsPanelSurface(cornerRadius: DSRadius.xl2, solid: true)
    }

    private var stepDivider: some View {
        Divider().overlay(DSColor.Foreground.divider).padding(.leading, DSSpacing.gap3)
    }

    private var modelRow: some View {
        HStack(spacing: DSSpacing.gap2) {
            stepIcon("sparkles")
            Text("Model")
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.muted)
            Spacer(minLength: DSSpacing.gap2)
            if availableModels.count > 1 {
                modelMenu
            } else {
                Text(form.model.label)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
            }
        }
        .padding(.horizontal, DSSpacing.gap3)
        .padding(.vertical, DSSpacing.gap2_5)
    }

    private var modelMenu: some View {
        Menu {
            ForEach(availableModels) { option in
                Button {
                    form.model = option
                    if option == .apple { form.expandedStep = nil }
                } label: {
                    if option == form.model {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: DSSpacing.gap1) {
                Text(form.model.label)
                    .dsTextStyle(.labelBase)
                Image(systemName: "chevron.down")
                    .font(.system(size: DSIconSize.xxs, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            .foregroundStyle(DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 28)
            .background(DSColor.Background.neutral, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(form.isGenerating)
    }

    private var styleStep: some View {
        collapsibleStep(
            step: .style,
            icon: "photo.on.rectangle.angled",
            title: "Style",
            summary: styleSummary
        ) {
            if form.usesCloudModel {
                styleGrid
                if form.style == .custom {
                    DSTextField(placeholder: "Describe a style…", text: $form.customStyleText)
                        .disabled(form.isGenerating)
                }
            } else {
                appleStepHint
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
            if form.usesCloudModel {
                viewGrid
            } else {
                appleStepHint
            }
        }
    }

    private var styleSummary: String {
        form.usesCloudModel ? form.style.label : "Apple Intelligence"
    }

    private var appleStepHint: some View {
        Text("Chosen in Apple Intelligence when you continue.")
            .dsTextStyle(.bodySmall)
            .foregroundStyle(DSColor.Foreground.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            if form.usesCloudModel {
                DSTextField(
                    placeholder: "Describe a background…",
                    validation: form.errorMessage == nil ? .normal : .error,
                    text: $form.prompt
                )
                .disabled(form.isGenerating)
            }
            if let errorMessage = form.errorMessage {
                Text(errorMessage)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Signal.error)
            }
            HStack(spacing: DSSpacing.gap1) {
                DSPrivacyBadge(tier: form.model.privacyTier == .appleCloud ? .appleCloud : .thirdParty)
                Text(modelFooter)
                    .dsTextStyle(.labelSmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }
        }
    }

    private var modelFooter: String {
        switch form.model {
        case .apple:
            return "0 credits · Apple Intelligence"
        case .gemini, .openAI:
            return "\(context.creditCost) credits · processed securely online"
        }
    }

    // MARK: - Actions

    private var footerNoteText: String {
        switch form.model {
        case .apple:
            return "Powered by Apple Intelligence. May create unexpected results."
        case .gemini:
            return "Powered by Gemini. May create unexpected results."
        case .openAI:
            return "Powered by OpenAI. May create unexpected results."
        }
    }

    private var actionRow: some View {
        VStack(spacing: DSSpacing.gap2) {
            Text(footerNoteText)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.subtle)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DSSpacing.gap2) {
                DSNeutralButton("Cancel", fullWidth: true) {
                    dismiss()
                }
                .disabled(form.isGenerating)
                DSPrimaryButton(
                    form.isGenerating ? "Generating…" : generateButtonTitle,
                    fullWidth: true
                ) {
                    Task { await generate() }
                }
                .disabled(!form.canGenerate)
            }
        }
    }

    private var generateButtonTitle: String {
        form.model == .apple ? "Continue" : "Generate"
    }

    // MARK: - Apple bridge

    @ViewBuilder
    private var applePlaygroundBridge: some View {
        #if canImport(ImagePlayground)
        if #available(macOS 15.1, *) {
            Color.clear
                .frame(width: 0, height: 0)
                .appleBackgroundPlaygroundSheet(
                    isPresented: $form.showApplePlayground,
                    onCompletion: handleAppleCompletion,
                    onCancellation: { form.showApplePlayground = false }
                )
        }
        #endif
    }

    private func alignDefaultModel() {
        let models = availableModels
        guard !models.isEmpty else { return }
        if !models.contains(form.model) {
            form.model = models.first ?? .gemini
        }
    }

    private func handleAppleCompletion(_ url: URL) {
        form.showApplePlayground = false
        guard let raw = ImagePlaygroundEntry.pngData(from: url),
              let stored = form.coordinator.persistToLibrary(raw) else {
            form.errorMessage = "Couldn't save the image."
            return
        }
        BackgroundGenerationCatalog.storeModel(.apple)
        onSaved(stored)
    }

    @MainActor
    private func generate() async {
        guard let entitlement else { return }

        if form.model == .apple {
            guard entitlement.allowAIFeature(.imagePlaygroundGenerate) else { return }
            #if canImport(ImagePlayground)
            if #available(macOS 15.1, *) {
                form.showApplePlayground = true
            }
            #endif
            return
        }

        guard entitlement.allowAIFeature(.backgroundGenerate) else { return }

        form.errorMessage = nil
        form.isGenerating = true
        BackgroundGenerationCatalog.storeModel(form.model)
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
private func presentGenerateBackground(
    context: BackgroundGenerationContext,
    entitlement: EntitlementModel?,
    applyAfterSave: Bool,
    onSaved: @escaping (Data) -> Void
) {
    guard let entitlement else { return }
    switch PrivacyPreferences2.shared.effectiveTier {
    case .onDevice:
        // E49.2: de allowAIFeature-call toont de elevation-modal — dan NIET
        // ook nog de generate-sheet openen (dubbele modal-bug).
        _ = entitlement.allowAIFeature(.backgroundGenerate)
        return
    case .appleCloud:
        guard entitlement.allowAIFeature(.imagePlaygroundGenerate) else { return }
    case .thirdParty:
        break
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
            .dsHoverScale()
            .help("Generate a background")
        }
    }

    @ViewBuilder
    private var swatchIcon: some View {
        if PrivacyPreferences2.shared.effectiveTier >= .thirdParty {
            DSIcon(.privacyAdvanced, size: 14, weight: .bold)
                .foregroundStyle(DSColor.Foreground.subtle)
        } else {
            DSIcon(.privacyAppleCloud, size: 14, weight: .bold)
                .foregroundStyle(DSColor.Foreground.subtle)
        }
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
        }
    }
}
