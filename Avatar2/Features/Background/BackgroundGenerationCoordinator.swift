// E42 — Gates, cloud-generatie en opslag voor AI-achtergronden.

import AvatarKit
import Foundation

enum BackgroundGenerationError: LocalizedError, Equatable {
    case useNativePlayground
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .useNativePlayground:
            return nil
        case .cancelled:
            return nil
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class BackgroundGenerationCoordinator {

    private var generationTask: Task<Data, Error>?

    func cancel() {
        generationTask?.cancel()
        generationTask = nil
    }

    /// Privacy-gate vóór het tonen van de sheet.
    @discardableResult
    func allowOpeningSheet(model: BackgroundGenerationModel, entitlement: EntitlementModel) -> Bool {
        switch model {
        case .apple:
            return entitlement.allowAIFeature(.imagePlaygroundGenerate)
        case .gemini, .openAI:
            return entitlement.allowAIFeature(.backgroundGenerate)
        }
    }

    func generate(
        model: BackgroundGenerationModel,
        context: BackgroundGenerationContext,
        style: BackgroundGenerationStyle,
        customStyleText: String,
        view: BackgroundGenerationView,
        prompt: String,
        entitlement: EntitlementModel
    ) async throws -> Data {
        generationTask?.cancel()
        let task = Task<Data, Error> {
            try await performGenerate(
                model: model,
                context: context,
                style: style,
                customStyleText: customStyleText,
                view: view,
                prompt: prompt,
                entitlement: entitlement
            )
        }
        generationTask = task
        defer { generationTask = nil }
        return try await task.value
    }

    private func performGenerate(
        model: BackgroundGenerationModel,
        context: BackgroundGenerationContext,
        style: BackgroundGenerationStyle,
        customStyleText: String,
        view: BackgroundGenerationView,
        prompt: String,
        entitlement: EntitlementModel
    ) async throws -> Data {
        try Task.checkCancellation()

        switch model {
        case .apple:
            throw BackgroundGenerationError.useNativePlayground
        case .gemini, .openAI:
            guard entitlement.allowAIFeature(.backgroundGenerate) else {
                throw BackgroundGenerationError.cancelled
            }
            let backend = entitlement.backend
            let userPrompt = BackgroundGenerationCatalog.sanitizedPrompt(prompt)
            let result = try await backend.generateBackground(
                userPrompt: userPrompt,
                styleKey: style.rawValue,
                customStyleText: style == .custom
                    ? BackgroundGenerationCatalog.sanitizedCustomStyle(customStyleText)
                    : nil,
                viewKey: view.rawValue,
                targetWidth: context.targetWidth,
                targetHeight: context.targetHeight,
                generationModel: model.generationModelKey
            )
            _ = result.creditsRemaining
            return result.imageData
        }
    }

    /// Sla op in de bibliotheek; retourneert downscaled PNG voor apply.
    func persistToLibrary(_ rawData: Data) -> Data? {
        BackgroundImageKit.shared.add(rawData)
    }
}
