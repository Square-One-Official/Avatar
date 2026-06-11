import CoreGraphics
import Foundation

/// Kiest welk cutout-pad een verzoek krijgt. Stub: registratie + eerste
/// beschikbare engine in voorkeursvolgorde. Echte routeringslogica
/// (kwaliteit/entitlement/fallback) komt in E02.
public struct PipelineRouter: Sendable {
    private let engines: [any CutoutEngine]

    public init(engines: [any CutoutEngine] = []) {
        self.engines = engines
    }

    /// De eerste beschikbare engine, optioneel met expliciete voorkeur.
    public func engine(preferring kind: CutoutEngineKind? = nil) async -> (any CutoutEngine)? {
        if let kind, let preferred = engines.first(where: { $0.kind == kind }),
           await preferred.isAvailable {
            return preferred
        }
        for candidate in engines where await candidate.isAvailable {
            return candidate
        }
        return nil
    }

    /// Routeert één cutout-verzoek naar de gekozen engine.
    public func cutout(_ image: CGImage, preferring kind: CutoutEngineKind? = nil) async throws -> CGImage {
        guard let engine = await engine(preferring: kind) else {
            throw CutoutEngineError.noEngineAvailable
        }
        return try await engine.cutout(image)
    }
}
