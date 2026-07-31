import CoreGraphics
import Foundation

/// Kiest welk cutout-pad een verzoek krijgt en **cascadeert bij een fout** naar
/// de overige beschikbare on-device engines: de voorkeur eerst, daarna de rest
/// in registratievolgorde (Vision is daarmee het altijd-aanwezige vangnet).
///
/// Cutout draait altijd on-device: Vision ("Regular quality") of het gedownloade
/// ORMBG-model ("High quality"). Er is geen cloud/credit-pad meer.
public struct PipelineRouter: Sendable {
    private let engines: [any CutoutEngine]

    public init(engines: [any CutoutEngine] = []) {
        self.engines = engines
    }

    /// De eerste beschikbare engine, optioneel met expliciete voorkeur.
    public func engine(preferring kind: CutoutEngineKind? = nil) async -> (any CutoutEngine)? {
        await orderedAvailableEngines(preferring: kind).first
    }

    /// Routeert één cutout-verzoek: probeert de voorkeurs-engine eerst en valt
    /// bij een fout terug op de volgende beschikbare engine. Faalt pas (met de
    /// laatste fout) als álle beschikbare engines falen — of `noEngineAvailable`
    /// als er geen beschikbaar is.
    public func cutout(_ image: CGImage, preferring kind: CutoutEngineKind? = nil) async throws -> CGImage {
        let ordered = await orderedAvailableEngines(preferring: kind)
        guard !ordered.isEmpty else { throw CutoutEngineError.noEngineAvailable }
        var lastError: Error?
        for engine in ordered {
            do {
                return try await engine.cutout(image)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CutoutEngineError.noEngineAvailable
    }

    /// Beschikbare engines in probeervolgorde: de voorkeur eerst (indien
    /// beschikbaar), daarna de overige beschikbare engines in registratie-
    /// volgorde, zonder dubbele kinds.
    private func orderedAvailableEngines(preferring kind: CutoutEngineKind?) async -> [any CutoutEngine] {
        var ordered: [any CutoutEngine] = []
        if let kind,
           let preferred = engines.first(where: { $0.kind == kind }),
           await preferred.isAvailable {
            ordered.append(preferred)
        }
        for candidate in engines where await candidate.isAvailable {
            if !ordered.contains(where: { $0.kind == candidate.kind }) {
                ordered.append(candidate)
            }
        }
        return ordered
    }
}
